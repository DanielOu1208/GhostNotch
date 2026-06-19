#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import pathlib
import shlex
import shutil
import tempfile
from dataclasses import dataclass


MANAGED_MARKER = "GHOSTNOTCH_MANAGED_HOOK=1"
PACKAGE_MARKER_NAME = "GHOSTNOTCH_HOOK_PACKAGE"
CONFIG_HOOKS_INTEGRATION = "configHooks"
PLUGIN_FILE_INTEGRATION = "pluginFile"
SCRIPT_DIRECTORY = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIRECTORY.parent
PACKAGE_DIRECTORY = SCRIPT_DIRECTORY / "agent-hook-packages"


@dataclass(frozen=True)
class HookSpec:
    event: str
    state: str
    matcher: str | None = None
    when_field: str | None = None


@dataclass(frozen=True)
class AgentHookPackage:
    package_id: str
    package_version: int
    display_name: str
    binary_name: str
    integration: str
    default_config_path: pathlib.Path
    helper_name: str
    legacy_helper_names: tuple[str, ...]
    hooks: tuple[HookSpec, ...]
    plugin_resource_path: pathlib.Path | None

    @property
    def marker(self) -> str:
        return f"{self.package_id}-v{self.package_version}"


def load_package(path: pathlib.Path) -> AgentHookPackage:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    integration = data.get("integration", CONFIG_HOOKS_INTEGRATION)
    if integration == CONFIG_HOOKS_INTEGRATION:
        raw_hooks = data["hooks"]
    elif integration == PLUGIN_FILE_INTEGRATION:
        raw_hooks = data.get("hooks", [])
        if not data.get("pluginResourcePath"):
            raise ValueError(f"{path} must define pluginResourcePath")
    else:
        raise ValueError(f"{path} has unsupported integration: {integration}")

    hooks = tuple(
        HookSpec(
            event=hook["event"],
            state=hook["state"],
            matcher=hook.get("matcher"),
            when_field=hook.get("whenField"),
        )
        for hook in raw_hooks
    )
    plugin_resource_path = data.get("pluginResourcePath")

    return AgentHookPackage(
        package_id=data["id"],
        package_version=int(data["packageVersion"]),
        display_name=data["displayName"],
        binary_name=data["binaryName"],
        integration=integration,
        default_config_path=pathlib.Path(data["defaultConfigPath"]).expanduser(),
        helper_name=data["helperName"],
        legacy_helper_names=tuple(data.get("legacyHelperNames", [])),
        hooks=hooks,
        plugin_resource_path=(REPOSITORY_ROOT / plugin_resource_path).resolve() if plugin_resource_path else None,
    )


def load_packages(package_directory: pathlib.Path = PACKAGE_DIRECTORY) -> tuple[AgentHookPackage, ...]:
    return tuple(load_package(path) for path in sorted(package_directory.glob("*.json")))


def hook_command(package: AgentHookPackage, hook: HookSpec) -> str:
    helper = f'"$GHOSTNOTCH_RESOURCES_DIR/{package.helper_name}"'
    helper_args = [
        "--agent",
        package.package_id,
        "--event",
        hook.event,
        "--state",
        hook.state,
    ]
    if hook.when_field:
        helper_args.extend(["--when-field", hook.when_field])

    quoted_args = " ".join(shlex.quote(arg) for arg in helper_args)
    package_marker = f"{PACKAGE_MARKER_NAME}={shlex.quote(package.marker)}"

    return (
        f'[ -n "$GHOSTNOTCH_RESOURCES_DIR" ] && '
        f'[ -x {helper} ] && '
        f'{MANAGED_MARKER} {package_marker} {helper} {quoted_args} || true'
    )


def managed_hook(package: AgentHookPackage, hook: HookSpec) -> dict:
    return {
        "type": "command",
        "command": hook_command(package, hook),
    }


def managed_block(package: AgentHookPackage, hook: HookSpec) -> dict:
    block = {"hooks": [managed_hook(package, hook)]}
    if hook.matcher is not None:
        block["matcher"] = hook.matcher
    return block


def hook_command_text(hook: object) -> str:
    if not isinstance(hook, dict):
        return ""
    command = hook.get("command", "")
    return command if isinstance(command, str) else ""


def is_package_hook(hook: object, package: AgentHookPackage) -> bool:
    return f"{PACKAGE_MARKER_NAME}={package.marker}" in hook_command_text(hook)


def is_legacy_package_hook(hook: object, package: AgentHookPackage) -> bool:
    command = hook_command_text(hook)
    return MANAGED_MARKER in command and any(helper_name in command for helper_name in package.legacy_helper_names)


def should_remove_hook(hook: object, package: AgentHookPackage, include_legacy: bool) -> bool:
    return is_package_hook(hook, package) or (include_legacy and is_legacy_package_hook(hook, package))


def remove_package_hooks(config: dict, package: AgentHookPackage, include_legacy: bool) -> dict:
    result = copy.deepcopy(config)
    hooks_by_event = result.get("hooks")
    if not isinstance(hooks_by_event, dict):
        return result

    for event_name in list(hooks_by_event.keys()):
        blocks = hooks_by_event.get(event_name)
        if not isinstance(blocks, list):
            continue

        kept_blocks = []
        for block in blocks:
            if not isinstance(block, dict):
                kept_blocks.append(block)
                continue

            hook_list = block.get("hooks")
            if not isinstance(hook_list, list):
                kept_blocks.append(block)
                continue

            kept_hooks = [
                hook
                for hook in hook_list
                if not should_remove_hook(hook, package, include_legacy)
            ]
            if kept_hooks:
                next_block = copy.deepcopy(block)
                next_block["hooks"] = kept_hooks
                kept_blocks.append(next_block)

        if kept_blocks:
            hooks_by_event[event_name] = kept_blocks
        else:
            hooks_by_event.pop(event_name, None)

    return result


def install_package_hooks(config: dict, package: AgentHookPackage) -> dict:
    result = remove_package_hooks(config, package, include_legacy=True)
    hooks_by_event = result.setdefault("hooks", {})
    if not isinstance(hooks_by_event, dict):
        result["hooks"] = {}
        hooks_by_event = result["hooks"]

    for hook in package.hooks:
        blocks = hooks_by_event.setdefault(hook.event, [])
        if not isinstance(blocks, list):
            hooks_by_event[hook.event] = []
            blocks = hooks_by_event[hook.event]

        blocks.append(managed_block(package, hook))

    return result


def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}

    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")

    return data


def write_json(path: pathlib.Path, data: dict, backup: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup and path.exists():
        timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        shutil.copy2(path, path.with_name(f"{path.name}.ghostnotch-backup-{timestamp}"))

    with path.open("w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


def apply_config(path: pathlib.Path, package: AgentHookPackage, action: str, backup: bool) -> None:
    current = load_json(path)
    if action == "install":
        updated = install_package_hooks(current, package)
    else:
        updated = remove_package_hooks(current, package, include_legacy=True)
    write_json(path, updated, backup=backup)


def backup_file(path: pathlib.Path) -> None:
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.ghostnotch-backup-{timestamp}"))


def install_plugin_file(path: pathlib.Path, package: AgentHookPackage, backup: bool) -> None:
    if package.plugin_resource_path is None:
        raise ValueError(f"{package.display_name} package is missing pluginResourcePath")
    if not package.plugin_resource_path.exists():
        raise FileNotFoundError(package.plugin_resource_path)

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        existing_text = path.read_text(encoding="utf-8", errors="replace")
        if MANAGED_MARKER not in existing_text:
            raise ValueError(f"{path} already exists and is not GhostNotch-managed")
        if backup:
            backup_file(path)

    shutil.copy2(package.plugin_resource_path, path)


def uninstall_plugin_file(path: pathlib.Path, backup: bool) -> None:
    if not path.exists():
        return

    existing_text = path.read_text(encoding="utf-8", errors="replace")
    if MANAGED_MARKER not in existing_text:
        return

    if backup:
        backup_file(path)
    path.unlink()


def apply_package(path: pathlib.Path, package: AgentHookPackage, action: str, backup: bool) -> None:
    if package.integration == CONFIG_HOOKS_INTEGRATION:
        apply_config(path, package, action, backup=backup)
        return
    if package.integration == PLUGIN_FILE_INTEGRATION:
        if action == "install":
            install_plugin_file(path, package, backup=backup)
        else:
            uninstall_plugin_file(path, backup=backup)
        return

    raise ValueError(f"Unsupported integration for {package.display_name}: {package.integration}")


def package_config_path(package: AgentHookPackage, args: argparse.Namespace) -> pathlib.Path:
    override = getattr(args, f"{package.package_id}_path", None)
    return override or package.default_config_path


def legacy_hook_command(helper_name: str, helper_args: str) -> str:
    helper = f'"$GHOSTNOTCH_RESOURCES_DIR/{helper_name}"'
    return (
        f'[ -n "$GHOSTNOTCH_RESOURCES_DIR" ] && '
        f'{MANAGED_MARKER} {helper} {helper_args} || true'
    )


def run_self_test() -> None:
    packages = {package.package_id: package for package in load_packages()}
    assert set(packages) == {"claude", "codex", "opencode"}

    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        codex_path = root / "codex" / "hooks.json"
        claude_path = root / "claude" / "settings.json"
        opencode_path = root / "opencode" / "plugins" / "ghostnotch-agent-indicator.js"
        codex_path.parent.mkdir()
        claude_path.parent.mkdir()

        codex_path.write_text(
            json.dumps(
                {
                    "hooks": {
                        "UserPromptSubmit": [
                            {
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": legacy_hook_command("ghostnotch-agent-state", "working"),
                                    }
                                ]
                            }
                        ],
                        "Stop": [
                            {
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": "echo existing",
                                    }
                                ]
                            }
                        ]
                    }
                }
            ),
            encoding="utf-8",
        )
        claude_path.write_text(
            json.dumps(
                {
                    "permissions": {"allow": ["mcp__pencil"]},
                    "hooks": {
                        "Notification": [
                            {
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": legacy_hook_command(
                                            "ghostnotch-agent-state",
                                            "attention --when-field notification_type=permission_prompt",
                                        ),
                                    }
                                ]
                            }
                        ]
                    },
                }
            ),
            encoding="utf-8",
        )

        apply_config(codex_path, packages["codex"], "install", backup=False)
        apply_config(codex_path, packages["codex"], "install", backup=False)
        codex = load_json(codex_path)
        codex_text = json.dumps(codex)
        assert codex_text.count(f"{PACKAGE_MARKER_NAME}=codex-v1") == len(packages["codex"].hooks)
        assert "ghostnotch-agent-hook" in codex_text
        assert "ghostnotch-agent-state" not in codex_text
        assert "ghostnotch-codex-hook" not in codex_text
        assert "echo existing" in codex_text

        apply_config(claude_path, packages["claude"], "install", backup=False)
        apply_config(claude_path, packages["claude"], "install", backup=False)
        claude = load_json(claude_path)
        claude_text = json.dumps(claude)
        assert claude["permissions"]["allow"] == ["mcp__pencil"]
        assert claude_text.count(f"{PACKAGE_MARKER_NAME}=claude-v1") == len(packages["claude"].hooks)
        assert "ghostnotch-agent-hook" in claude_text
        assert "ghostnotch-agent-state" not in claude_text
        assert "elicitation_dialog" in claude_text

        combined = install_package_hooks(codex, packages["claude"])
        combined = remove_package_hooks(combined, packages["codex"], include_legacy=True)
        combined_text = json.dumps(combined)
        assert f"{PACKAGE_MARKER_NAME}=codex-v1" not in combined_text
        assert f"{PACKAGE_MARKER_NAME}=claude-v1" in combined_text

        apply_config(codex_path, packages["codex"], "uninstall", backup=False)
        apply_config(claude_path, packages["claude"], "uninstall", backup=False)
        assert f"{PACKAGE_MARKER_NAME}=codex-v1" not in codex_path.read_text(encoding="utf-8")
        assert f"{PACKAGE_MARKER_NAME}=claude-v1" not in claude_path.read_text(encoding="utf-8")
        assert "echo existing" in codex_path.read_text(encoding="utf-8")

        apply_package(opencode_path, packages["opencode"], "install", backup=False)
        apply_package(opencode_path, packages["opencode"], "install", backup=False)
        opencode_text = opencode_path.read_text(encoding="utf-8")
        assert MANAGED_MARKER in opencode_text
        assert "GhostNotchAgentIndicator" in opencode_text
        assert "session.status" in opencode_text
        apply_package(opencode_path, packages["opencode"], "uninstall", backup=False)
        assert not opencode_path.exists()

        opencode_path.write_text("// user plugin\n", encoding="utf-8")
        try:
            apply_package(opencode_path, packages["opencode"], "install", backup=False)
        except ValueError as error:
            assert "not GhostNotch-managed" in str(error)
        else:
            raise AssertionError("Expected unmanaged OpenCode plugin collision to fail")
        assert opencode_path.read_text(encoding="utf-8") == "// user plugin\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install or uninstall GhostNotch agent indicator hooks.")
    parser.add_argument("action", choices=["install", "uninstall", "self-test"])
    parser.add_argument("--codex-path", type=pathlib.Path)
    parser.add_argument("--claude-path", type=pathlib.Path)
    parser.add_argument("--opencode-path", type=pathlib.Path)
    parser.add_argument("--force", action="store_true", help="Write config even if the CLI executable is not detected.")
    parser.add_argument("--no-backup", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.action == "self-test":
        run_self_test()
        return 0

    backup = not args.no_backup
    for package in load_packages():
        config_path = package_config_path(package, args)
        if args.force or shutil.which(package.binary_name) or config_path.exists():
            try:
                apply_package(config_path, package, args.action, backup=backup)
            except (FileNotFoundError, ValueError) as error:
                raise SystemExit(f"error: {package.display_name}: {error}") from error
            print(f"{args.action}: {package.display_name} hooks at {config_path}")
        else:
            print(f"skip: {package.display_name} not found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

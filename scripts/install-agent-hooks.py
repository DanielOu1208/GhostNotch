#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import pathlib
import shutil
import tempfile


MANAGED_MARKER = "GHOSTNOTCH_MANAGED_HOOK=1"


CODEX_HOOKS = {
    "SessionStart": [("idle", None)],
    "UserPromptSubmit": [("working", None)],
    "Stop": [("idle", None)],
    "PermissionRequest": [("attention", "*")],
}

CLAUDE_HOOKS = {
    "SessionStart": [("idle", None)],
    "UserPromptSubmit": [("working", None)],
    "Stop": [("idle", None)],
    "StopFailure": [("idle", None)],
    "SessionEnd": [("idle", None)],
    "PermissionRequest": [("attention", "*")],
    "Notification": [("attention --when-field notification_type=permission_prompt,idle_prompt,elicitation_dialog", None)],
    "Elicitation": [("attention", "*")],
    "ElicitationResult": [("working", "*")],
}


def hook_command(state_args: str) -> str:
    helper = '"$GHOSTNOTCH_RESOURCES_DIR/ghostnotch-agent-state"'
    return (
        f'[ -n "$GHOSTNOTCH_RESOURCES_DIR" ] && '
        f'[ -x {helper} ] && '
        f'{MANAGED_MARKER} {helper} {state_args} || true'
    )


def managed_hook(state_args: str) -> dict:
    return {
        "type": "command",
        "command": hook_command(state_args),
    }


def managed_block(state_args: str, matcher: str | None) -> dict:
    block = {"hooks": [managed_hook(state_args)]}
    if matcher is not None:
        block["matcher"] = matcher
    return block


def is_managed_hook(hook: object) -> bool:
    return isinstance(hook, dict) and MANAGED_MARKER in str(hook.get("command", ""))


def remove_managed_hooks(config: dict) -> dict:
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

            kept_hooks = [hook for hook in hook_list if not is_managed_hook(hook)]
            if kept_hooks:
                next_block = copy.deepcopy(block)
                next_block["hooks"] = kept_hooks
                kept_blocks.append(next_block)

        if kept_blocks:
            hooks_by_event[event_name] = kept_blocks
        else:
            hooks_by_event.pop(event_name, None)

    return result


def install_hooks(config: dict, hook_map: dict[str, list[tuple[str, str | None]]]) -> dict:
    result = remove_managed_hooks(config)
    hooks_by_event = result.setdefault("hooks", {})
    if not isinstance(hooks_by_event, dict):
        result["hooks"] = {}
        hooks_by_event = result["hooks"]

    for event_name, hooks in hook_map.items():
        blocks = hooks_by_event.setdefault(event_name, [])
        if not isinstance(blocks, list):
            hooks_by_event[event_name] = []
            blocks = hooks_by_event[event_name]

        for state_args, matcher in hooks:
            blocks.append(managed_block(state_args, matcher))

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


def apply_config(path: pathlib.Path, hook_map: dict[str, list[tuple[str, str | None]]], action: str, backup: bool) -> None:
    current = load_json(path)
    updated = install_hooks(current, hook_map) if action == "install" else remove_managed_hooks(current)
    write_json(path, updated, backup=backup)


def run_self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        codex_path = root / "codex" / "hooks.json"
        claude_path = root / "claude" / "settings.json"
        codex_path.parent.mkdir()
        claude_path.parent.mkdir()

        codex_path.write_text(
            json.dumps(
                {
                    "hooks": {
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
        claude_path.write_text(json.dumps({"permissions": {"allow": ["mcp__pencil"]}}), encoding="utf-8")

        apply_config(codex_path, CODEX_HOOKS, "install", backup=False)
        apply_config(codex_path, CODEX_HOOKS, "install", backup=False)
        codex = load_json(codex_path)
        stop_hooks = str(codex["hooks"]["Stop"])
        assert stop_hooks.count(MANAGED_MARKER) == 1
        assert "echo existing" in stop_hooks
        assert MANAGED_MARKER in str(codex["hooks"]["PermissionRequest"])

        apply_config(claude_path, CLAUDE_HOOKS, "install", backup=False)
        apply_config(claude_path, CLAUDE_HOOKS, "install", backup=False)
        claude = load_json(claude_path)
        assert claude["permissions"]["allow"] == ["mcp__pencil"]
        assert str(claude["hooks"]["Notification"]).count(MANAGED_MARKER) == 1
        assert "elicitation_dialog" in str(claude["hooks"]["Notification"])

        apply_config(codex_path, CODEX_HOOKS, "uninstall", backup=False)
        apply_config(claude_path, CLAUDE_HOOKS, "uninstall", backup=False)
        assert MANAGED_MARKER not in codex_path.read_text(encoding="utf-8")
        assert MANAGED_MARKER not in claude_path.read_text(encoding="utf-8")
        assert "echo existing" in codex_path.read_text(encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install or uninstall GhostNotch Codex/Claude indicator hooks.")
    parser.add_argument("action", choices=["install", "uninstall", "self-test"])
    parser.add_argument("--codex-path", type=pathlib.Path, default=pathlib.Path.home() / ".codex" / "hooks.json")
    parser.add_argument("--claude-path", type=pathlib.Path, default=pathlib.Path.home() / ".claude" / "settings.json")
    parser.add_argument("--force", action="store_true", help="Write config even if the CLI executable is not detected.")
    parser.add_argument("--no-backup", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.action == "self-test":
        run_self_test()
        return 0

    backup = not args.no_backup
    if args.force or shutil.which("codex") or args.codex_path.exists():
        apply_config(args.codex_path, CODEX_HOOKS, args.action, backup=backup)
        print(f"{args.action}: Codex hooks at {args.codex_path}")
    else:
        print("skip: Codex CLI not found")

    if args.force or shutil.which("claude") or args.claude_path.exists():
        apply_config(args.claude_path, CLAUDE_HOOKS, args.action, backup=backup)
        print(f"{args.action}: Claude Code hooks at {args.claude_path}")
    else:
        print("skip: Claude Code not found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

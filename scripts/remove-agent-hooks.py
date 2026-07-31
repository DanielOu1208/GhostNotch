#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import os
import pathlib
import shutil
import stat
import tempfile


PACKAGE_MARKERS = (
    "GHOSTNOTCH_HOOK_PACKAGE=codex-v",
    "GHOSTNOTCH_HOOK_PACKAGE=claude-v",
)
LEGACY_HELPERS = (
    "ghostnotch-agent-hook",
    "ghostnotch-agent-state",
    "ghostnotch-codex-hook",
)


def is_managed_hook(hook: object) -> bool:
    if not isinstance(hook, dict):
        return False
    command = hook.get("command")
    if not isinstance(command, str):
        return False
    if any(marker in command for marker in PACKAGE_MARKERS):
        return True
    return "GHOSTNOTCH_MANAGED_HOOK=1" in command and any(
        helper in command for helper in LEGACY_HELPERS
    )


def remove_managed_hooks(config: dict) -> dict:
    result = copy.deepcopy(config)
    hooks_by_event = result.get("hooks")
    if not isinstance(hooks_by_event, dict):
        return result

    for event_name, blocks in list(hooks_by_event.items()):
        if not isinstance(blocks, list):
            continue

        kept_blocks = []
        for block in blocks:
            if not isinstance(block, dict) or not isinstance(block.get("hooks"), list):
                kept_blocks.append(block)
                continue

            kept_hooks = [hook for hook in block["hooks"] if not is_managed_hook(hook)]
            if kept_hooks:
                next_block = copy.deepcopy(block)
                next_block["hooks"] = kept_hooks
                kept_blocks.append(next_block)

        if kept_blocks:
            hooks_by_event[event_name] = kept_blocks
        else:
            hooks_by_event.pop(event_name)

    return result


def load_json(path: pathlib.Path) -> dict:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def write_json_atomic(path: pathlib.Path, data: dict, backup: bool) -> None:
    if backup:
        timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        shutil.copy2(path, path.with_name(f"{path.name}.ghostnotch-backup-{timestamp}"))

    mode = stat.S_IMODE(path.stat().st_mode)
    temporary_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as temporary_file:
            json.dump(data, temporary_file, indent=2)
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
            temporary_path = pathlib.Path(temporary_file.name)

        temporary_path.chmod(mode)
        temporary_path.replace(path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def clean_config(path: pathlib.Path, backup: bool = True) -> bool:
    if not path.exists():
        return False
    resolved_path = path.resolve(strict=True)
    current = load_json(resolved_path)
    updated = remove_managed_hooks(current)
    if updated == current:
        return False
    write_json_atomic(resolved_path, updated, backup)
    return True


def run_self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        codex_path = root / "codex" / "hooks.json"
        claude_path = root / "claude" / "settings.json"
        codex_path.parent.mkdir()
        claude_path.parent.mkdir()

        unrelated = {"type": "command", "command": "echo keep-me"}
        codex_original = {
            "hooks": {
                "Stop": [{"matcher": "*", "hooks": [
                    unrelated,
                    {"type": "command", "command": "GHOSTNOTCH_MANAGED_HOOK=1 ghostnotch-agent-state idle"},
                    {"type": "command", "command": "GHOSTNOTCH_HOOK_PACKAGE=codex-v9 run-hook"},
                ]}],
                "Malformed": "leave-alone",
            },
            "other": {"enabled": True},
        }
        claude_original = {
            "permissions": {"allow": ["mcp__example"]},
            "hooks": {"Notification": [{"hooks": [
                {
                    "type": "command",
                    "command": "GHOSTNOTCH_HOOK_PACKAGE=claude-v1 $GHOSTNOTCH_RESOURCES_DIR/ghostnotch-agent-hook --agent claude",
                }
            ]}]},
        }
        codex_path.write_text(json.dumps(codex_original), encoding="utf-8")
        claude_path.write_text(json.dumps(claude_original), encoding="utf-8")
        codex_path.chmod(0o640)

        assert clean_config(codex_path)
        assert clean_config(claude_path)
        codex = load_json(codex_path)
        claude = load_json(claude_path)
        assert codex["hooks"]["Stop"][0]["hooks"] == [unrelated]
        assert codex["hooks"]["Malformed"] == "leave-alone"
        assert codex["other"] == {"enabled": True}
        assert claude == {"permissions": {"allow": ["mcp__example"]}, "hooks": {}}
        assert stat.S_IMODE(codex_path.stat().st_mode) == 0o640

        codex_backups = list(codex_path.parent.glob("hooks.json.ghostnotch-backup-*"))
        claude_backups = list(claude_path.parent.glob("settings.json.ghostnotch-backup-*"))
        assert len(codex_backups) == len(claude_backups) == 1
        assert json.loads(codex_backups[0].read_text(encoding="utf-8")) == codex_original
        assert json.loads(claude_backups[0].read_text(encoding="utf-8")) == claude_original
        assert not clean_config(codex_path)
        assert len(list(codex_path.parent.glob("hooks.json.ghostnotch-backup-*"))) == 1
        assert not clean_config(root / "missing.json")

        linked_target = root / "shared" / "settings.json"
        linked_target.parent.mkdir()
        linked_target.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [
            unrelated,
            {"type": "command", "command": "GHOSTNOTCH_MANAGED_HOOK=1 ghostnotch-agent-state idle"},
        ]}]}}), encoding="utf-8")
        linked_path = root / "linked-settings.json"
        linked_path.symlink_to(linked_target)

        assert clean_config(linked_path)
        assert linked_path.is_symlink()
        assert load_json(linked_target)["hooks"]["Stop"][0]["hooks"] == [unrelated]
        assert len(list(linked_target.parent.glob("settings.json.ghostnotch-backup-*"))) == 1

        unrelated_managed_hook = {
            "type": "command",
            "command": "GHOSTNOTCH_MANAGED_HOOK=1 different-ghostnotch-helper",
        }
        assert not is_managed_hook(unrelated_managed_hook)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Remove obsolete GhostNotch Codex and Claude status hooks.")
    parser.add_argument("--codex-path", type=pathlib.Path, default=pathlib.Path.home() / ".codex" / "hooks.json")
    parser.add_argument("--claude-path", type=pathlib.Path, default=pathlib.Path.home() / ".claude" / "settings.json")
    parser.add_argument("--no-backup", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        run_self_test()
        return 0

    for name, path in (("Codex", args.codex_path), ("Claude", args.claude_path)):
        if clean_config(path, backup=not args.no_backup):
            print(f"removed: GhostNotch {name} hooks from {path}")
        else:
            print(f"unchanged: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Agent Indicator Hooks

GhostNotch drives the collapsed agent indicator from explicit Codex CLI and Claude Code hook state. It does not infer agent work from PTY output.

## Install

```sh
python3 scripts/install-agent-hooks.py install
```

The installer merges GhostNotch hook entries into:

- `~/.codex/hooks.json`
- `~/.claude/settings.json`

It preserves existing hooks, avoids duplicate GhostNotch entries, and creates timestamped backups before writing.

## Uninstall

```sh
python3 scripts/install-agent-hooks.py uninstall
```

The uninstaller removes only hook commands marked as GhostNotch-managed.

## States

- `idle`: steady white dot
- `working`: pulsing white dot
- `attention`: amber attention dot

Codex and Claude hooks write these states through the bundled `ghostnotch-agent-state` helper when launched inside GhostNotch. Other terminal programs and agents remain idle unless they call the helper explicitly.

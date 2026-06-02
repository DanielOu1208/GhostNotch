# Agent Indicator Hooks

GhostNotch drives the collapsed agent indicator from explicit Codex CLI and Claude Code hook state. It does not infer agent work from PTY output.

## Indicator States

- `idle`: steady green dot
- `working`: breathing white dot
- `attention`: breathing blue dot

Other terminal programs and agents remain idle unless they call a GhostNotch helper explicitly.

## Install

```sh
python3 scripts/install-agent-hooks.py install
```

The installer merges GhostNotch hook entries into:

- `~/.codex/hooks.json`
- `~/.claude/settings.json`

It preserves existing hooks, avoids duplicate GhostNotch entries, and creates timestamped backups before writing.

Hook package definitions live in `scripts/agent-hook-packages/`. Adding another supported agent should start with a new manifest instead of adding another hardcoded installer branch.

Codex requires hook trust for changed command definitions. After installing or updating GhostNotch hooks, open `/hooks` in Codex CLI and trust the GhostNotch-managed entries if Codex reports that review is needed.

## Uninstall

```sh
python3 scripts/install-agent-hooks.py uninstall
```

The uninstaller removes only hook commands marked for the matching GhostNotch hook package. It also removes legacy GhostNotch-managed entries listed by that package manifest.

## Codex Hooks

Codex hooks write structured JSON state through the bundled `ghostnotch-agent-hook` helper when launched inside GhostNotch.

Current Codex mapping:

- `SessionStart`: `idle`
- `UserPromptSubmit`: `working`
- `PreToolUse`: `working`
- `PostToolUse`: `working`
- `PermissionRequest`: `attention`
- `Stop`: `idle`

Normal Codex replies and option pickers that ask a question are not treated as `attention` unless Codex exposes a reliable hook signal for that case.

Codex `working` states expire back to rendered `idle` after a short freshness timeout when no newer hook arrives. This prevents the collapsed indicator from pulsing forever while Codex is blocked on an option picker that does not emit a hook. The state file is not rewritten during this timeout; only the rendered app state changes.

## Claude Hooks

Claude hooks use the same bundled `ghostnotch-agent-hook` helper and structured JSON state format.

Current Claude mapping:

- `SessionStart`: `idle`
- `UserPromptSubmit`: `working`
- `Stop`: `idle`
- `StopFailure`: `idle`
- `SessionEnd`: `idle`
- `PermissionRequest`: `attention`
- `Notification` with `permission_prompt`, `idle_prompt`, or `elicitation_dialog`: `attention`
- `Elicitation`: `attention`
- `ElicitationResult`: `working`

## State Envelope

Codex and Claude state files are JSON envelopes:

```json
{
  "version": 1,
  "agent": "codex",
  "state": "working",
  "event": "UserPromptSubmit",
  "timestamp": "2026-06-01T00:00:00.000Z",
  "payloadKeys": ["hook_event_name"],
  "payloadTypes": {
    "hook_event_name": "str"
  }
}
```

GhostNotch accepts structured envelopes where `agent` is `codex` or `claude` and `state` is `idle`, `working`, or `attention`. Invalid JSON, unknown agents, unknown states, missing state files, and stopped sessions resolve to `idle`.

Legacy raw state files are still accepted during migration:

```text
working
```

## Runtime Files

When GhostNotch starts the terminal session, it exposes two per-session paths to child processes:

- `GHOSTNOTCH_AGENT_STATE_FILE`: the state file GhostNotch polls for indicator updates.
- `GHOSTNOTCH_AGENT_EVENT_LOG`: optional JSONL diagnostics written by `ghostnotch-agent-hook`.

The event log is intentionally metadata-only. Entries may include agent name, event name, timestamp, payload keys, and payload value types. They must not include raw prompts, commands, assistant text, terminal output, nested secret values, or other payload contents.

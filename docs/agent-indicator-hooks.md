# Agent Indicator Hooks

GhostNotch drives the collapsed agent indicator from explicit Codex CLI, Claude Code, and OpenCode activity state. It does not infer agent work from PTY output.

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

The installer also copies the managed OpenCode plugin to:

- `~/.config/opencode/plugins/ghostnotch-agent-indicator.js`

It preserves existing Codex and Claude hooks, avoids duplicate GhostNotch entries, and creates timestamped backups before writing. For OpenCode, it only overwrites or removes the managed GhostNotch plugin file; an unrelated file at the same path is left untouched and reported as a collision.

Hook package definitions live in `scripts/agent-hook-packages/`. Adding another supported agent should start with a new manifest instead of adding another hardcoded installer branch. A hook package can install command hooks into a JSON config file or install a managed plugin file, depending on the agent's extension model.

Codex requires hook trust for changed command definitions. After installing or updating GhostNotch hooks, open `/hooks` in Codex CLI and trust the GhostNotch-managed entries if Codex reports that review is needed.

## Uninstall

```sh
python3 scripts/install-agent-hooks.py uninstall
```

The uninstaller removes only hook commands marked for the matching GhostNotch hook package. It also removes legacy GhostNotch-managed entries listed by that package manifest. For OpenCode, it removes only the managed plugin file.

## Codex Hooks

Codex hooks write structured JSON state through the bundled `ghostnotch-agent-hook` helper when launched inside GhostNotch.

Current Codex mapping:

- `SessionStart`: `idle`
- `UserPromptSubmit`: `working`
- `PreToolUse`: `working`
- `PostToolUse`: `working`
- `PermissionRequest`: `attention`
- `Stop`: `idle`

Normal Codex replies are not treated as `attention` unless Codex exposes a reliable hook signal for that case.

Codex user selectors do not currently expose a documented hook signal. While the latest structured Codex hook state is `working`, GhostNotch also checks the rendered terminal snapshot for strict selector markers. Supported selector snapshots are:

- Question selectors with `Question N/N`, `unanswered`, numbered choices, `enter to submit answer`, and `esc to interrupt`.
- Plan-finished implementation selectors with `Implement this plan?`, the three implementation choices, and `Press enter to confirm or esc to go back`.

When those markers remain visible for the 200ms confirmation window, the rendered indicator becomes `attention` until the visible snapshot no longer matches a supported selector.

## Recent Implementation Challenges

- Codex selectors look interactive to the user, but Codex still reports fresh structured `working` hooks while the selector is visible. The rendered snapshot must therefore remain the source of truth for keeping the indicator `attention`; newer `PreToolUse` or `PostToolUse` hooks alone must not clear that override.
- Explicit attention hooks still take precedence. A structured Codex `PermissionRequest` clears the visible selector override and renders `attention`, because approval prompts require the user's attention even if the terminal still contains selector-like text.
- Snapshot-derived Codex selector attention is delayed by 200ms to reduce false positives from transient output that briefly resembles a selector. Hook-derived attention, such as `PermissionRequest`, is not delayed.
- Picker redraw lag came from treating Ghostty dirty-row metadata as reusable across collapse and expansion. A selector snapshot can be current but already `clean`, so terminal-surface activation now captures the current snapshot and requests a full grid redraw instead of waiting for another dirty row.
- Terminal snapshots continue flowing through `TerminalSurfaceCoordinator` while collapsed so selector detection is not coupled to expansion timing. Avoid storing raw selector text in session state; the override only needs to remember whether a strict selector is visible.
- Keep this behavior covered by focused tests: visible selectors hold `attention` through fresh Codex `working` hooks, non-selector snapshots return to `working`, `PermissionRequest` remains `attention`, and clean-snapshot activation forces a full redraw.

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

## OpenCode Plugin

OpenCode uses JavaScript plugins for lifecycle events instead of Codex or Claude-style command-hook config. GhostNotch installs a managed plugin file that listens for OpenCode events, then calls the same bundled `ghostnotch-agent-hook` helper used by the other agents.

Current OpenCode mapping:

- `PluginStart`: `idle`
- `session.status` with `busy` or `retry`: `working`
- `session.status` with `idle`: `idle`
- `session.idle`: `idle`
- `session.error`: `idle`
- `permission.asked`, `permission.updated`, or `question.asked`: `attention`
- `permission.replied`, `question.replied`, or `question.rejected`: `working`

`permission.updated` is kept for the older installed OpenCode event shape, while `permission.asked` matches the newer event name in the current OpenCode docs.

## State Envelope

Codex, Claude, and OpenCode state files are JSON envelopes:

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

GhostNotch accepts structured envelopes where `agent` is `codex`, `claude`, or `opencode` and `state` is `idle`, `working`, or `attention`. Invalid JSON, unknown agents, unknown states, missing state files, and stopped sessions resolve to `idle`.

Legacy raw state files are still accepted during migration:

```text
working
```

## Runtime Files

When GhostNotch starts the terminal session, it exposes two per-session paths to child processes:

- `GHOSTNOTCH_AGENT_STATE_FILE`: the state file GhostNotch polls for indicator updates.
- `GHOSTNOTCH_AGENT_EVENT_LOG`: optional JSONL diagnostics written by `ghostnotch-agent-hook`.

The event log is intentionally metadata-only. Entries may include agent name, event name, timestamp, payload keys, payload value types, and allowlisted scalar payload values such as `hook_event_name`, `notification_type`, and `tool_name`. They must not include raw prompts, commands, assistant text, terminal output, nested secret values, or other payload contents.

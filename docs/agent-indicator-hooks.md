# Agent Status Detection

GhostNotch derives status for Codex, Claude, OpenCode, Cursor CLI, OMP, Pi,
and Droid from the terminal it already owns. It does not install or read agent
lifecycle hooks for status.

The terminal is the single status authority because agent hooks do not cover
every interruption, permission result, compaction, or process-exit path. A live
terminal signal can correct the indicator on the next update instead of leaving
a stale state file behind.

## Visible States

GhostNotch keeps the existing three presentation states:

- `idle` renders the static system-green Rose Three and the label `Ready`.
- `working` renders the animated white/primary Rose Three and `Working`.
- `attention` renders the animated system-blue Rose Three and `Waiting`.

The collapsed left wing shows the active supported-agent asset in monochrome
primary for the lifetime of that process, including its Ready state. It is blank
when no supported agent is running. With Reduce Motion enabled, the rose stays
static and agent identity changes immediately.

## Status Authority

Each update uses three kinds of evidence from the current terminal session:

1. A read-only descendant-process check identifies a running supported agent
   and its process ID.
2. The terminal bridge exposes live bottom-grid text independently of the
   user-scrolled viewport, plus terminal title and progress signals.
3. Small, ordered agent-specific rules classify that evidence as Ready,
   Working, Waiting, or preserve the previous state.

Process identity and terminal evidence belong to the same process lifetime. A
process exit or same-agent relaunch clears retained evidence before the next
classification, preventing a new session from inheriting an old prompt.

Working-to-Ready changes receive a short confirmation window to avoid flicker
from partial redraws. An explicit live Ready prompt, Working signal, Waiting
prompt, agent change, or process exit takes effect without waiting for that
confirmation. Unmatched content from a known supported agent resolves to Ready
rather than keeping stale activity forever.

## Codex Signals

Codex classification gives the strongest current signal priority:

- An action-required title or a strict visible confirmation, question,
  permission, or submission form means Waiting.
- A spinner title means Working.
- The transcript viewer preserves the previous state because it is an overlay,
  not a lifecycle transition.
- An ordinary current title or visible prompt means Ready.
- Other content from a running Codex process falls back to Ready.

## Claude Signals

Claude uses the same single-authority model with Claude-specific terminal
signals:

- A spinner title or active background-work overlay means Working.
- A strict permission, elicitation, or interactive form means Waiting.
- The transcript viewer and model picker preserve the previous state because
  they are overlays.
- A visible prompt, idle title, or completed progress signal means Ready.
- Other content from a running Claude process falls back to Ready.

## Additional Agent Signals

The five additional profiles follow the same process-and-terminal model:

- OpenCode recognizes its permission choices, activity labels, spinner, and
  composer.
- Cursor CLI recognizes its command-approval prompt, activity labels, spinner,
  and composer.
- OMP uses its documented `π >`, `π ⠋`, and `π !` terminal-title states, with
  visible prompt fallbacks.
- Pi recognizes its project-trust prompt, activity labels, spinner, and
  composer.
- Droid recognizes its permission choices, activity labels, spinner, and
  composer.

Unmatched content from any known supported-agent process falls back to Ready.

## Why There Are No Status Hooks

Agent hooks are useful integrations, but they do not describe a complete
terminal lifecycle. An agent can be interrupted or transition through UI that
has no matching hook. Combining hooks with terminal rules also creates two
competing answers for one indicator.

GhostNotch therefore keeps process identity and live terminal evidence as the
only status source. This follows the single-authority behavior described by
[Herdr](https://herdr.dev/docs/agents/), but GhostNotch's Swift rules are an
independent clean-room implementation. Herdr source and manifests are not
copied into this MIT-licensed project.

## Remove Legacy GhostNotch Hooks

Users who installed an earlier GhostNotch status-hook package can remove only
those managed entries with:

```sh
python3 scripts/remove-agent-hooks.py
```

The cleanup utility checks Codex and Claude configuration, preserves unrelated
configuration and third-party hooks, and creates a timestamped backup before a
change. GhostNotch does not run it automatically because those files belong to
the user.

No environment variables, state envelopes, event logs, hook trust step, or
agent configuration changes are required for current status detection. Old
hook output is ignored by the app until the user removes it.

## Privacy and Validation

Terminal text used for classification stays in memory and is not written to a
status log. Rules use only the bounded live terminal evidence needed to choose
the visible state.

Automated coverage and the manual supported-agent acceptance matrix are
documented in [Testing](testing.md). Automated checks do not replace live
validation of real agent versions, permissions, interruptions, compaction,
scrollback, and process exit.

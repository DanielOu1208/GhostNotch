# Pre-Feature Hardening Acceptance - 2026-06-10

This note records the terminal/status baseline before starting the next feature work.

## Verified

- Full automated suite passed:

  ```sh
  xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
  ```

- Codex selector hardening is covered by focused tests:
  - Question selectors with strict markers resolve from `working` to `attention` after the dwell window.
  - Plan-finished `Implement this plan?` selectors resolve from `working` to `attention` after the dwell window.
  - Fresh Codex `working` hooks do not clear a confirmed visible selector.
  - Non-selector snapshots return the indicator to `working`.
  - `PermissionRequest` remains immediate `attention`.

- Hook installer self-test passed:

  ```sh
  python3 scripts/install-agent-hooks.py self-test
  ```

- Hook helper privacy/state self-test passed:

  ```sh
  python3 GhostNotch/Resources/ShellIntegration/ghostnotch-agent-hook --self-test
  ```

- GhostNotch hook entries were installed into:
  - `~/.codex/hooks.json`
  - `~/.claude/settings.json`

- Installed hook config was verified after install:
  - Codex has 6 `codex-v1` GhostNotch-managed hook entries.
  - Claude has 9 `claude-v1` GhostNotch-managed hook entries.
  - Legacy `ghostnotch-agent-state` and `ghostnotch-codex-hook` entries are absent.

- Installed hook commands were smoke-tested against temporary state and event-log files:
  - Codex `UserPromptSubmit` writes structured `working`.
  - Codex `PermissionRequest` writes structured `attention`.
  - Claude `Elicitation` writes structured `attention`.
  - Claude `Notification` writes structured `attention` only for the allowed notification types.
  - Event logs include metadata only and did not include the test prompt or command payload text.

## Not Verified In This Agent Run

The expanded macOS app visual/manual pass still needs to be run interactively in GhostNotch. This tool session can run builds, tests, scripts, and command-level hook smoke tests, but it cannot reliably inspect and interact with the real expanded island UI.

Required manual checks remain the same as `docs/testing.md`:

- Primary shell scrollback stays on the same visible lines after collapse/reopen.
- `less` stays on the same visible lines after collapse/reopen when cols/rows do not change.
- `vim` or `nano` does not jump unexpectedly after collapse/reopen when cols/rows do not change.
- Trackpad/wheel scroll works in `less`.
- Mouse-enabled TUI press/release/drag behavior does not inject visible garbage.
- ANSI/style, box/block glyphs, Powerline glyphs, cursor alignment, paste, Escape routing, and CJK/wide-cell copy remain visually correct in the expanded island.

## Baseline Decision

The code and command-level status/hook baseline is ready for new feature work. The remaining risk is real expanded-app visual behavior, so terminal-renderer or input-heavy features should still start by rerunning the manual checks above.

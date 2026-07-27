# Testing

This guide covers the current local verification path for GhostNotch.

## Build

Confirm the canonical project and scheme:

```sh
xcodebuild -list -project GhostNotch.xcodeproj
```

Build a Debug app:

```sh
xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Debug build
```

Build and run the newest local app with a clean terminal-host context:

```sh
scripts/run-local.sh
```

Set `CONFIGURATION=Debug` when needed. Use this launcher instead of calling
`open` directly from an agent or terminal multiplexer: macOS passes the
caller's environment to apps launched with `open`, including temporary values
such as `NO_COLOR` and Herdr pane ownership. The launcher preserves ordinary
user environment values while removing that host-only context.

## Automated Tests

Run the app and terminal tests:

```sh
xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
```

Exercise the legacy GhostNotch hook cleanup without changing user files:

```sh
python3 scripts/remove-agent-hooks.py --self-test
```

The automated suite covers shell resolution, real PTY command output, session
stopping, input mapping, Ghostty-backed terminal snapshots, ANSI styles, cursor
behavior, scrollback, graphemes, wide cells, paste encoding, resize behavior,
focus events, mouse encoding, and selected Ghostty comparison streams. It also
checks process identity, title/progress parsing, terminal rules for all seven
supported agents, transition stabilization, process exit and relaunch, and
legacy-hook cleanup.

## Manual Terminal Acceptance

Manual expanded-app acceptance still needs to be run interactively in GhostNotch after renderer or terminal behavior changes.

Latest pre-feature hardening note: [Pre-Feature Hardening Acceptance - 2026-06-10](pre-feature-hardening-acceptance-2026-06-10.md).

Required checks:

- Primary shell scrollback stays on the same visible lines after collapse/reopen.
- `less` stays on the same visible lines after collapse/reopen when cols/rows do not change.
- `vim` or `nano` does not jump unexpectedly after collapse/reopen when cols/rows do not change.
- Trackpad/wheel scroll works in `less`.
- Mouse-enabled TUI press/release/drag behavior does not inject visible garbage.
- ANSI/style, box/block glyphs, Powerline glyphs, cursor alignment, paste, Escape routing, and CJK/wide-cell copy remain visually correct in the expanded island.

### Supported Agent Status

Run these checks with Codex, Claude, OpenCode, Cursor CLI, OMP, Pi, and Droid,
using both a launcher-started agent and an agent typed directly into the shell:

- The agent asset appears while its process is alive and clears when it exits.
- A normal prompt shows Ready; active generation or tool work shows Working;
  permissions, questions, and other required input show Waiting.
- Approving, denying, or cancelling a prompt clears Waiting from current
  terminal evidence alone.
- Escape interruption and compaction do not leave a stuck state or briefly
  report a false Ready state.
- In Codex and Claude, opening a transcript viewer or model picker does not
  replace the state behind the overlay.
- Scrolling into history while the agent continues to run does not make old
  visible text drive the current state.
- Restarting the same agent clears the previous process's terminal evidence.
- Ready remains static with Reduce Motion, and Working/Waiting remain readable
  in collapsed and hover states.

Useful commands:

```sh
printf 'plain\n  indented\nred: \033[31mred\033[0m bold: \033[1mbold\033[0m\n'
printf 'style: \033[2mfaint\033[0m \033[4munder\033[0m \033[4:2mdouble\033[0m \033[4:3mcurly\033[0m \033[4:4mdotted\033[0m \033[4:5mdashed\033[0m \033[9mstrike\033[0m \033[53mover\033[0m \033[7minverse\033[0m\n'
printf 'color: \033[38;5;196mansi256-fg\033[0m \033[48;5;24mansi256-bg\033[0m \033[38;2;1;180;255mtruecolor-fg\033[0m \033[48;2;64;32;96mtruecolor-bg\033[0m\n'
printf 'unicode: é 🙂 界 \n'
printf 'powerline:    \n'
printf 'box: ┌─┬─┐ ╔═╦═╗ ╭─╮ ╱╲╳\n     │ ┼ │ ╠═╬═╣ ╰─╯ ┃┋┊\n     └─┴─┘ ╚═╩═╝\n'
printf 'blocks: ▁▂▃▄▅▆▇█ ▏▎▍▌▋▊▉█ ▖▗▘▝▚▞▙▛▜▟ ░▒▓█\n'
printf 'wide columns: |界|x|  copy this line and verify no duplicate wide spacer\n'
CLICOLOR=1 ls -G
top
less docs/testing.md
vim docs/testing.md # or nano if vim is unavailable
```

Notes:

- Powerline/private-use glyphs require an installed compatible developer font such as MesloLGS NF, JetBrainsMono Nerd Font, Hack Nerd Font, or FiraCode Nerd Font.
- `TERM` intentionally remains `xterm-256color`; `TERM_PROGRAM=GhostNotch`, GhostNotch version metadata, and `COLORTERM=truecolor` are set by the PTY environment.
- Focused-terminal Escape should reach the terminal program. Use `Option+Space`, the close button, or outside click for app-level collapse.

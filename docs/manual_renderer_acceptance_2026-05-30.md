# Manual Renderer Acceptance Notes - 2026-05-30

## Context

This note records the post-hardening acceptance status after the R6, R7, and R8 code baselines were implemented.

Automated coverage now includes:

- Mouse-tracking press, drag, release, and wheel encoding.
- Primary scrollback, alternate-screen wheel fallback, duplicate resize suppression, and dirty-row invalidation.
- ANSI 16/256/truecolor, extended decorations, underline variants, inverse, cursor style, grapheme, emoji, CJK, private-use glyph, and wide-cell copy model behavior.
- Ghostty comparison streams for prompt text, hyperlink negotiation, and graphics negotiation pass-through.

## Automated Result

Run:

```sh
xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
```

Result: passed after the R8 mouse-event boundary patch.

## Manual Status

Manual expanded-app acceptance still needs to be run interactively in GhostNotch.

Required checks:

- Primary shell scrollback stays on the same visible lines after collapse/reopen.
- `less` stays on the same visible lines after collapse/reopen when cols/rows do not change.
- `vim` or `nano` does not jump unexpectedly after collapse/reopen when cols/rows do not change.
- Trackpad/wheel scroll works in `less`.
- Mouse-enabled TUI press/release/drag behavior does not inject visible garbage.
- ANSI/style, box/block glyphs, Powerline glyphs, cursor alignment, paste, Escape routing, and CJK/wide-cell copy remain visually correct in the expanded island.

## Notes

- The terminal font diagnostic log reports the selected font and whether it supports the Powerline separator glyph.
- `TERM` intentionally remains `xterm-256color`; `TERM_PROGRAM=GhostNotch`, GhostNotch version metadata, `COLORTERM=truecolor`, and `GHOSTNOTCH_RESOURCES_DIR` are now set by the PTY environment.

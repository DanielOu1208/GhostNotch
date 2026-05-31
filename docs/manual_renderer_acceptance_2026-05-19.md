# Manual Renderer Acceptance Findings - 2026-05-19

## Context

Manual acceptance was run against the current GhostNotch terminal renderer after the automated renderer/session baseline passed.

The current docs still track this work under:

- `R6 - Font features and ligature pass`
- `R7 - Color/style presentation pass`
- `R8 - Mouse, selection, and alternate-screen behavior hardening`

The tester reported that the basic shell, ANSI/style rendering, wide-cell copy, paste, Escape routing, and most TUI/editor rendering checks were otherwise acceptable.

## Automated Baseline

Command:

```sh
xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
```

Result: passed.

This means the issues below are runtime/manual-app acceptance gaps, not current unit-test regressions.

## Observed Results

### 1. Private-use prompt glyph renders as a missing-glyph box

Manual command:

```sh
printf 'unicode: é 🙂 界 \n'
```

Observed:

- The private-use `` glyph renders as a box with a question mark.
- The wide-space copy test copied correctly:

```text
wide columns: |界|x|  copy this line and verify no duplicate wide spacer
```

Reasoning:

- This is probably not a grapheme or wide-cell bug. The wide-cell copy result is correct, and the private-use glyph is not a standard Unicode character with universal font coverage.
- `` is a Powerline/Nerd Font private-use glyph. If no compatible Nerd Font is installed, a missing-glyph box is expected.
- If a compatible Nerd Font is installed and GhostNotch still shows the box, then the renderer font selection/fallback path is too weak. The current grid renderer prefers a short list of font names and falls back through CoreText per string, but private-use glyph fallback can still fail if the installed font's actual family/PostScript name does not match the preferred list or CoreText chooses a fallback without that glyph.

Issue status:

- Expected if no Nerd Font is installed.
- An R6 issue if a compatible Nerd Font is installed but GhostNotch does not select it or fall back to it.

Possible measures:

1. Document the dependency clearly in the manual test: Powerline/private-use glyphs require a Nerd Font such as MesloLGS NF, JetBrainsMono Nerd Font, Hack Nerd Font, or FiraCode Nerd Font.
2. Add a lightweight font diagnostic log or debug UI that reports the selected terminal font family and whether it can render the test glyph.
3. Expand font discovery beyond hard-coded display names by checking installed font descriptors for known Nerd Font traits/names.
4. Add a terminal font setting later, so users can explicitly choose the installed font GhostNotch should use.
5. Treat bundling a font as a product decision, not a renderer default. Bundling would make the glyph predictable but adds licensing, app-size, and user-preference considerations.

Recommended next action:

- First confirm whether a Nerd Font is installed on the test machine. If not, this is a documentation/setup note. If yes, make this the first R6 font-selection bug.

### 2. Trackpad scrolling does not work inside `less` or `vim`

Manual programs:

```sh
less docs/ghostnotch_mvp_spec.md
vim docs/ghostnotch_mvp_spec.md
```

Observed:

- Trackpad scrolling does not scroll inside `less`.
- Trackpad scrolling does not scroll inside `vim`.

Reasoning:

- This is expected from the current implementation, but it is still an R8 acceptance gap.
- The terminal grid currently handles wheel events only when the snapshot is not in alternate screen. `less` and `vim` normally use alternate screen, so GhostNotch does not translate the wheel event into terminal input for those programs.
- The app also does not yet implement full terminal mouse reporting. If a foreground TUI enables mouse tracking, the correct behavior is to encode mouse wheel events and send them to the PTY. If it does not enable mouse tracking, a pragmatic terminal behavior is to translate wheel deltas into navigation keys such as Up/Down or PageUp/PageDown.

Issue status:

- Expected current behavior.
- Real R8 issue because the acceptance criteria say wheel behavior should not fight `less`/`vim`/`top`.

Possible measures:

1. Minimal fallback: when in alternate screen and mouse tracking is off, translate wheel deltas into Up/Down or PageUp/PageDown key events and send them through the existing Ghostty key encoder.
2. More terminal-correct path: expose Ghostty mouse encoder support through `GhosttyVTBridge` and send wheel events when mouse tracking is enabled.
3. Hybrid policy: implement the fallback for no mouse tracking, and use Ghostty mouse encoding when mouse tracking is active.
4. Add manual regression checks for `less`, `vim` or `nano`, and `top`, because each program has slightly different expectations.

Recommended next action:

- Implement the hybrid policy under R8. It keeps normal scrollback behavior on the primary screen, makes `less`/`vim` usable immediately, and leaves room for correct mouse-mode behavior when a TUI explicitly asks for it.

### 3. Collapse/reopen does not return to the same visible lines

Manual action:

- Open a TUI or scrolled view.
- Scroll to a visible position.
- Collapse GhostNotch.
- Reopen GhostNotch.

Observed:

- The screen is not on the same lines after returning to expanded state.

Reasoning:

- The shell process appears to stay alive, so this is probably not a session-lifecycle failure.
- The likely problem is viewport and size stability across the SwiftUI/AppKit view lifecycle. Collapsing replaces the expanded terminal view with the collapsed indicator. Reopening recreates the grid view, requests focus, and reports size again. That can trigger a terminal resize or redraw even when the visual expanded size did not meaningfully change.
- In alternate-screen programs such as `less` and `vim`, a resize/redraw can move or recompute the visible region. In primary-screen scrollback, the renderer also needs to preserve the Ghostty viewport offset intentionally instead of accidentally snapping back.

Issue status:

- Real R8 issue if the program/session is still alive but visible viewport state is not stable.
- Higher priority than visual polish because it affects trust in collapse/reopen.

Possible measures:

1. Cache the last expanded terminal grid dimensions and avoid sending a resize on re-expand when cols/rows are unchanged.
2. Preserve the renderer viewport position across collapse/reopen, especially for primary-screen scrollback.
3. Distinguish user-initiated viewport movement from automatic follow-bottom behavior, so reopening does not snap unexpectedly.
4. Add a focused test around `GhosttyTerminalCore` viewport preservation if the needed state is exposed by the bridge.
5. Add a manual R8 check that records behavior separately for primary shell scrollback, `less`, and `vim`, because the root causes may differ.

Recommended next action:

- Start by suppressing redundant resize on re-expand. It is the smallest likely fix and should reduce alternate-screen redraw movement. If the problem remains, add explicit viewport-position preservation.

## Prioritized Fix Order

1. Manual rerun of R8 collapse/reopen viewport stability after duplicate-resize and selection-clearing hardening.
2. Manual rerun of R8 alternate-screen wheel and mouse behavior for `less`, `vim`/`nano`, and `top`.
3. Manual R6/R7 prompt, glyph, font fallback, color, and style pass after the font-discovery and diagnostics baseline.

This order keeps the next work focused on behavioral correctness before visual polish, matching the current MVP implementation order.

## Acceptance Checks For The Next Patch

- Primary shell scrollback stays on the same visible lines after collapse/reopen.
- `less` stays on the same visible lines after collapse/reopen when cols/rows do not change.
- `vim` or `nano` does not jump unexpectedly after collapse/reopen when cols/rows do not change.
- Trackpad/wheel scroll works in `less`.
- Mouse-enabled TUI press/release/drag behavior does not inject visible garbage.
- Powerline glyph behavior is classified as either missing-font setup or renderer font-selection bug, using the terminal font diagnostic log.

## Rendering Fidelity Fixture Commands

Use these commands for the next manual render pass focused specifically on TUI visual fidelity:

```sh
printf 'style: \033[2mfaint\033[0m \033[4munder\033[0m \033[4:2mdouble\033[0m \033[4:3mcurly\033[0m \033[4:4mdotted\033[0m \033[4:5mdashed\033[0m \033[9mstrike\033[0m \033[53mover\033[0m \033[7minverse\033[0m\n'
printf 'color: \033[38;5;196mansi256-fg\033[0m \033[48;5;24mansi256-bg\033[0m \033[38;2;1;180;255mtruecolor-fg\033[0m \033[48;2;64;32;96mtruecolor-bg\033[0m\n'
printf 'powerline:    \n'
printf 'box: ┌─┬─┐ ╔═╦═╗ ╭─╮ ╱╲╳\n     │ ┼ │ ╠═╬═╣ ╰─╯ ┃┋┊\n     └─┴─┘ ╚═╩═╝\n'
printf 'blocks: ▁▂▃▄▅▆▇█ ▏▎▍▌▋▊▉█ ▖▗▘▝▚▞▙▛▜▟ ░▒▓█\n'
python3 - <<'PY'
try:
    from rich.console import Console
    from rich.panel import Panel
    Console().print(Panel.fit("rich border sample", border_style="cyan"))
except Exception:
    print("rich not installed; skip rich border sample")
PY
command -v gum >/dev/null && gum style --border rounded --padding '0 1' 'gum border sample' || true
```

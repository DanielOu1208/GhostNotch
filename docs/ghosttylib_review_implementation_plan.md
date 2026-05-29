# Ghosttylib Review Implementation Plan

Date: 2026-05-24

This checklist tracks implementation work from `docs/ghosttylib_deep_code_review.md`.
The production path remains the vendored `libghostty-vt` boundary plus the
GhostNotch AppKit renderer while a separate full Ghostty surface spike evaluates
whether a later migration is worth doing.

## Decisions

- Production architecture: parallel tracks, with VT-first hardening plus a
  separate full Ghostty surface feasibility spike.
- Rename scope: documentation/comments and low-churn aliases first; no broad
  source rename in the first implementation slice.
- First slice success: cleanup plus `TerminalSurfaceCoordinator` extraction and
  basic output coalescing.
- Mouse scope: hybrid wheel behavior only. Full mouse press/release/drag
  reporting remains later work.

## VT-First Production Work

- [x] Clarify the current boundary as `libghostty-vt`, not full `libghostty`.
- [x] Preserve measured terminal cell geometry across restart.
- [x] Build static status snapshots without constructing a Ghostty terminal core.
- [x] Move terminal session/engine policy behind `TerminalSurfaceCoordinator`.
- [x] Coalesce PTY output before rendering a snapshot.
- [x] Reduce default session state from retained raw output to lifecycle state
  plus `hasReceivedOutput`, keeping explicit test/debug capture available.
- [x] Surface render dirty state and dirty rows from `GhosttyVTBridge`.
- [x] Use dirty rows for targeted AppKit invalidation where feasible.
- [x] Implement hybrid scroll wheel behavior:
  - primary screen scrolls the Ghostty viewport;
  - alternate screen without mouse tracking sends navigation keys;
  - mouse tracking uses Ghostty mouse wheel encoding.

## Full Ghostty Surface Spike

- [ ] Add or build a full Ghostty embedding artifact that exposes
  `include/ghostty.h`, `ghostty_app_t`, `ghostty_config_t`, and
  `ghostty_surface_t`.
- [ ] Create a temporary macOS `NSView` spike that creates app/config/surface,
  attaches it to an `NSView`, sets size/scale/display/focus, launches a shell,
  and verifies render, key input, scroll, paste, and focus behavior.
- [ ] Record the result in a short spike report with a continue-VT or migrate-to-
  surface recommendation.

Current blocker: the checked-in vendor artifact exposes `libghostty-vt` headers,
not full `libghostty` surface embedding headers. The spike requires a new
artifact/provenance step before implementation can be meaningful.

## Verification

- Run:

```sh
xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
```

- Manual acceptance after automated tests:
  - shell startup, restart, and focus;
  - `less`, `vim`, and `top` wheel behavior;
  - bracketed paste in prompts and full-screen TUIs;
  - focus reporting remains gated by terminal mode;
  - no obvious compact-island rendering regression.

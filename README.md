# GhostNotch

GhostNotch is an early experimental macOS app that turns the MacBook notch into a tiny terminal island.

It sits flush with the top of the display, looks like an extension of the hardware notch, and expands into a compact terminal when you need to run quick shell commands. The goal is not to replace a full terminal app. The goal is a fast, notch-native utility for short terminal interactions that can stay alive quietly in the background.

## Status

GhostNotch is a prototype-stage project. It is usable for local development and experimentation, but it is not packaged, signed, or documented as a normal end-user install yet.

Current focus:

- Keep the notch-attached island interaction fast and reliable.
- Harden the embedded terminal for real shell and TUI use.
- Keep the Ghostty-backed rendering boundary honest and replaceable.
- Document the remaining MVP work in small, testable chunks.

Not ready yet:

- Packaged releases.
- Public install instructions.
- App Store distribution.
- Full Ghostty renderer or shell-integration parity.
- A polished settings/preferences surface.

## What It Does

GhostNotch shows a small active island around the MacBook notch. The island has three main states:

- **Collapsed:** a subtle notch extension with activity indicators.
- **Hover:** a larger preview state that does not take keyboard focus.
- **Expanded:** a compact terminal panel with keyboard focus.

When expanded, GhostNotch starts a persistent shell session, renders terminal output, accepts keyboard input and paste, and keeps the session alive when the island collapses again.

The current product hotkey is:

```text
Option+Space
```

That toggles the terminal between expanded and collapsed states.

## How It Works

GhostNotch is a native macOS app built with Swift, AppKit, SwiftUI, and a native PTY-backed terminal session.

At a high level:

1. `AppDelegate` creates the menu bar item and the notch island panel.
2. `IslandPanelController` owns the floating panel, state transitions, focus behavior, and the single terminal session.
3. `PTYProcess` starts the user's shell in a pseudo-terminal.
4. `TerminalSession` keeps the PTY process alive and exposes input, output, resize, and lifecycle state.
5. `GhosttyTerminalEngine` feeds PTY output into a Ghostty-backed terminal core.
6. `TerminalGridSurfaceView` draws the resulting terminal grid in the expanded island.

The terminal path uses a vendored `libghostty-vt` artifact for VT parsing, terminal state, key encoding, paste encoding, focus events, render snapshots, and terminal query write-back behavior. GhostNotch still owns the AppKit/CoreText grid renderer and the notch-specific UI.

That distinction matters: GhostNotch currently uses Ghostty's VT/render-state boundary. It does not embed Ghostty's full renderer, configuration system, shell integration, or terminal application behavior.

## Tech Stack

- **Language:** Swift, C
- **UI:** AppKit, SwiftUI
- **Platform:** macOS
- **Windowing:** borderless `NSPanel` attached visually to the notch
- **Terminal process:** native PTY
- **Terminal parsing/state:** vendored `libghostty-vt`
- **Rendering:** GhostNotch-owned AppKit/CoreText terminal grid
- **Project:** root `GhostNotch.xcodeproj`

## Repository Layout

```text
GhostNotch/
├── GhostNotch/                 # App source
│   ├── Terminal/               # PTY, shell session, Ghostty VT bridge, render model
│   ├── UI/                     # Island and terminal grid views
│   └── Window/                 # NSPanel, positioning, outside-click behavior
├── GhostNotchTests/            # Unit tests
├── docs/                       # MVP spec and notch geometry research
├── scripts/                    # Vendor/build helper scripts
├── vendor/ghostty-vt/          # Pinned Ghostty VT artifact and headers
└── GhostNotch.xcodeproj        # Canonical Xcode project
```

Use the root `GhostNotch.xcodeproj` and root `GhostNotch/` source tree. Older duplicate project/source copies should not be used.

## Current Capabilities

The current implementation includes:

- Notch-attached collapsed, hover, and expanded island states.
- Persistent default-shell PTY session started on first expand.
- Session preservation across collapse and reopen.
- Keyboard input, Ghostty-backed special-key encoding, paste, focus/blur encoding, and resize propagation.
- Grid-based terminal rendering through a vendored Ghostty VT boundary.
- ANSI style handling, cursor movement, alternate-screen support, scrollback viewport control, grapheme-aware snapshots, wide-cell metadata, and app-level terminal text selection/copy.
- Product toggle hotkey with `Option+Space`.
- Debug notch-fill toggle for visual testing.

## Current Limitations

GhostNotch is still early. The important known gaps are:

- No packaged release or public install flow yet.
- Manual renderer acceptance still needs to be run in real shell/TUI scenarios like `top`, `less`, `vim`, and `nano`.
- Font feature, ligature, fallback-font, color/style, mouse, selection, and alternate-screen behavior still need polish.
- Shell integration is conservative: the app currently avoids advertising a Ghostty-style terminal identity until terminfo and shell-resource behavior are deliberately implemented.
- Runtime notch measurement and non-notch display fallback behavior still need more work.
- The debug notch color control should be removed or hidden before a public MVP build.

See the MVP spec for the detailed work packages.

## Documentation

- [MVP specification](docs/ghostnotch_mvp_spec.md) is the implementation source of truth.
- [MacBook notch geometry research](docs/notch_geometry_research.md) records the notch sizing and positioning assumptions.
- [Ghostty VT vendor notes](vendor/ghostty-vt/README.md) describe the vendored terminal artifact.

## Contributing

This project is still changing quickly, so the best contribution path is to work from the current MVP spec rather than guessing from the README.

Useful areas for collaborators:

- Renderer acceptance testing in real terminal programs.
- Font, glyph, color, cursor, and selection polish.
- Shell identity, terminfo, and shell integration design.
- Runtime notch measurement across different MacBook models and external displays.
- Keeping the Ghostty boundary narrow, explicit, and replaceable.

When changing terminal behavior, keep the architecture boundary intact:

- Panel and SwiftUI code should not depend directly on Ghostty C types.
- `GhosttyVTBridge` should isolate unstable C API details.
- `GhosttyTerminalCore`, `GhosttyTerminalEngine`, and `TerminalRenderSnapshot` should remain the stable app-facing terminal boundary.
- Documentation should say GhostNotch is Ghostty-backed, not Ghostty-equivalent, until the app actually embeds a fuller Ghostty renderer or shell integration stack.

## Project Direction

GhostNotch is exploring a focused idea: a terminal that feels built into the MacBook notch instead of floating as another desktop window.

The near-term goal is a reliable MVP for quick commands and compact shell workflows. Broader terminal-app features like tabs, panes, profiles, plugin systems, advanced theming, and full Ghostty compatibility are intentionally out of scope for now.

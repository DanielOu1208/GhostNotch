# Architecture

GhostNotch is a native macOS app built with Swift, AppKit, SwiftUI, a native PTY session, and a vendored Ghostty VT boundary.

## App Shape

At a high level:

1. `AppDelegate` creates the menu bar item and notch island panel.
2. `IslandPanelController` owns the floating panel, state transitions, focus behavior, and the single terminal surface coordinator.
3. `TerminalSurfaceCoordinator` owns the terminal session and rendering engine pair.
4. `PTYProcess` starts the user's shell in a pseudo-terminal.
5. `TerminalSession` keeps the PTY process alive and exposes input, output, resize, startup, and lifecycle state.
6. `GhosttyTerminalEngine` feeds PTY output into the Ghostty-backed terminal core.
7. The AppKit/CoreText grid renderer draws the resulting terminal snapshot.

The terminal backend is intentionally not owned by SwiftUI views. Window and panel behavior stay in the window layer; shell lifecycle, PTY output batching, terminal rendering, resize, focus, scroll, and restart policy stay in the terminal layer.

## Ghostty Boundary

GhostNotch uses a vendored `libghostty-vt` artifact for VT parsing, terminal state, render snapshots, key encoding, paste encoding, focus events, scrollback viewport control, mouse encoding, and terminal query write-back behavior.

GhostNotch does not embed Ghostty's full renderer, configuration system, shell integration, or terminal application behavior. The current production path is a Ghostty-backed VT/render-state boundary plus a GhostNotch-owned AppKit/CoreText renderer.

Keep this boundary explicit:

- Panel and SwiftUI code should not depend directly on Ghostty C types.
- `GhosttyVTBridge` should isolate unstable C API details.
- `GhosttyTerminalCore`, `GhosttyTerminalEngine`, and `TerminalRenderSnapshot` should remain the stable app-facing terminal boundary.
- Terminal grid rendering should stay decomposed into focused rendering, typography, decoration, pixel-grid, and AppKit key-mapping modules.

## Source Layout

```text
GhostNotch/
├── Terminal/   # PTY, shell session, Ghostty VT bridge, input, render model
├── UI/         # Island views and modular terminal grid renderer
└── Window/     # NSPanel, positioning, outside-click behavior
```

Use the root `GhostNotch.xcodeproj` and root `GhostNotch/` source tree. Historical duplicate project/source copies are not part of the current repo shape.

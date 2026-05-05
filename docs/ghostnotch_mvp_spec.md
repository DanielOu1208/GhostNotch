# GhostNotch MVP Specification

## Current Implementation Baseline

GhostNotch is a native macOS Dynamic-Island-style terminal utility. The current codebase has completed the Stage 1 floating island shell and notch geometry work, but it does not yet contain a real terminal backend.

The canonical project is the root Xcode project:

```text
GhostNotch.xcodeproj
```

That project builds source files from:

```text
GhostNotch/
├── AppDelegate.swift
├── GhostNotchApp.swift
├── Window/
└── UI/
```

The duplicate project/source copy has been removed. Future implementation work should use the root project and root `GhostNotch/` source tree.

## Product Goal

Build a tiny floating terminal island for macOS that:

- Sits visually at the MacBook notch.
- Extends subtly beyond the physical notch so users can tell the app is active.
- Expands on hover for a preview state.
- Expands on click into a compact terminal panel with keyboard focus.
- Keeps one terminal session alive while collapsed.
- Uses Ghostty's terminal engine through `libghostty` / `ghosttylib` if embedding proves feasible.
- Feels like a notch-native utility, not a normal terminal window.

The MVP should prioritize a reliable native shell, fast interaction, and polished notch integration over advanced terminal features.

## Completed Stage 1 Scope

The current implementation already includes:

- Native Swift macOS app shell.
- AppKit lifecycle through `AppDelegate`.
- Menu bar item with `>_` label.
- Floating borderless `NSPanel` implementation.
- Non-activating collapsed and hover states.
- Key-focus accepting expanded state.
- Top-flush notch-extension geometry.
- Collapsed, hover, and expanded visual states.
- Hover-driven preview expansion.
- Click-to-expand behavior.
- Escape-to-collapse behavior.
- Local and global outside-click collapse.
- Status-bar-level panel placement.
- All-Spaces/full-screen auxiliary collection behavior.
- Stage 1 placeholder terminal UI.
- Debug notch fill color toggle via menu item and `Command+Option+G`.

The current terminal content is mock UI only. It displays placeholder commands and output; it does not run a shell or preserve a PTY session yet.

## Current Implemented Architecture

```text
GhostNotch/
├── GhostNotchApp.swift
├── AppDelegate.swift
│
├── Window/
│   ├── IslandPanel.swift
│   ├── IslandPanelController.swift
│   ├── WindowPositioner.swift
│   └── OutsideClickMonitor.swift
│
└── UI/
    ├── IslandRootView.swift
    ├── IslandIndicatorView.swift
    └── IslandExpandedView.swift
```

### App Shell

`AppDelegate` is responsible for:

- Setting `NSApp` activation policy to `.regular`.
- Creating the menu bar item.
- Showing the island panel on launch.
- Expanding the island from the menu item.
- Installing the temporary notch color debug hotkey.
- Cleaning up the hotkey and panel on termination.

### Window System

`IslandPanel` subclasses `NSPanel` and controls key eligibility through `shouldAcceptKeyFocus`.

Current focus behavior:

- Collapsed and hover states use `.nonactivatingPanel`.
- Expanded state removes `.nonactivatingPanel`, activates the app, and makes the panel key.
- Escape key is intercepted in `IslandPanel.keyDown` and routed to collapse.

`IslandPanelController` owns:

- `state: IslandState`
- `notchFillMode: NotchFillMode`
- Panel creation and configuration.
- Expand/collapse transitions.
- Hover state transitions.
- Outside-click monitor lifecycle.

Current panel configuration:

```text
isOpaque: false
backgroundColor: clear
hasShadow: false
level: statusBar
hidesOnDeactivate: false
isMovable: false
collectionBehavior: canJoinAllSpaces, fullScreenAuxiliary, stationary
animationBehavior: none
```

### Positioning

`WindowPositioner` currently centers the island horizontally on the main screen and pins it flush to the top of the screen:

```swift
x = screenFrame.midX - size.width / 2
y = screenFrame.maxY - size.height
```

This intentionally differs from an ordinary floating capsule below the menu bar. The visual should read as a hardware notch extension.

Current metrics:

```text
physicalNotchReferenceWidth: 220 pt
collapsedSize: 280 x 38 pt
hoverSize: 420 x 72 pt
expandedSize: 680 x 320 pt
```

The 220 pt reference comes from local notch research in `docs/notch_geometry_research.md`.

### UI System

`IslandRootView` renders a custom top-flush `NotchExtensionShape` with only the lower corners rounded.

Current shape behavior:

- Top edge is flat.
- Top edge is flush with the screen top.
- Bottom corners are rounded.
- Collapsed and hover radius: 14 pt.
- Expanded radius: 18 pt.

`NotchFillMode` currently supports:

- `.black`
- `.darkGray`

This is a Stage 1 debug aid for visually comparing the software fill against the real hardware notch. It should not be treated as an end-user MVP setting yet.

`IslandIndicatorView` keeps the center hardware-notch region visually clear in collapsed state and places active indicators in the side extensions:

- Left extension: Ghostty-style mark.
- Center gap: physical notch reference width.
- Right extension: green status dot.

Hover state shows:

- `default shell ready`
- green active dot
- `>_`
- `ready`

`IslandExpandedView` currently renders:

- 38 pt top clear area matching the physical notch height.
- Header row.
- Placeholder terminal lines.
- Escape hint.

## MVP User Experience

The MVP should behave as follows:

```text
User sees a subtle active island attached to the notch.
User hovers the island.
Island grows into a preview without taking keyboard focus.
User clicks the island.
Island expands into a compact terminal and accepts keyboard input.
User runs quick shell commands.
User presses Escape or clicks elsewhere.
Island collapses back into the notch extension.
The shell session continues running in the background.
```

## MVP Scope Still To Implement

### Terminal Session

Add one persistent terminal session:

- Use the user's default shell.
- Start in the user's home directory.
- Keep the shell process alive while collapsed.
- Preserve terminal buffer while collapsed.
- Reopen into the same session.
- Resize the terminal backend when the island size changes.

Default shell resolution:

```text
1. Use SHELL environment variable if valid.
2. Fallback to /bin/zsh.
```

### Terminal Rendering

Preferred rendering path:

```text
libghostty / ghosttylib
```

The terminal UI should be abstracted so the app shell does not depend directly on Ghostty internals.

Recommended abstraction:

```swift
protocol TerminalRenderingEngine {
    func start(session: TerminalSession)
    func sendInput(_ input: Data)
    func resize(cols: Int, rows: Int)
    func focus()
    func blur()
}
```

If Ghostty embedding is blocked or unstable, implement a temporary native PTY-backed fallback behind the same abstraction. Do not mix terminal process management into `IslandPanelController` or SwiftUI views.

### Suggested Terminal Files

Add a `Terminal/` module under the canonical root source tree:

```text
GhostNotch/Terminal/
├── TerminalSession.swift
├── PTYProcess.swift
├── ShellResolver.swift
├── TerminalRenderingEngine.swift
├── GhosttyBridge.swift
├── GhosttyTerminalView.swift
└── TerminalSessionState.swift
```

Responsibilities:

- `TerminalSession`: lifecycle of the single session.
- `PTYProcess`: pseudo-terminal process setup, read/write, resize, cleanup.
- `ShellResolver`: default shell lookup and validation.
- `TerminalRenderingEngine`: rendering/input abstraction.
- `GhosttyBridge`: Ghostty-specific integration boundary.
- `GhosttyTerminalView`: SwiftUI/AppKit wrapper for the terminal renderer.
- `TerminalSessionState`: observable state needed by the UI.

### Input and Focus

The current panel focus behavior should stay:

- Collapsed: no keyboard focus.
- Hover: no keyboard focus.
- Expanded: accepts keyboard focus.

Terminal implementation must add:

- Text input routing into the terminal engine.
- Paste support.
- Basic modifier key handling.
- Resize propagation.
- Focus/blur calls to the renderer.

Escape should continue to collapse the island, but terminal input should be handled carefully so Escape can still be sent to terminal programs in a future enhancement.

### Product Hotkey

The current `Command+Option+G` hotkey is only for toggling the notch test fill color.

The MVP terminal toggle hotkey is still not implemented. Recommended default:

```text
Option+Space
```

Expected behavior:

```text
Collapsed or hover -> expand and focus terminal.
Expanded -> collapse.
```

When adding this, keep it separate from the debug color hotkey. The debug hotkey can be removed before a public MVP build.

## Geometry Requirements

The notch geometry work is part of the product behavior, not a temporary styling detail.

Current local measurement:

```text
physical notch reference: 220 x 38 pt
```

The MVP should preserve these principles:

- Use top-flush geometry.
- Keep the top edge flat.
- Avoid pill-shaped collapsed geometry.
- Put visible active indicators in the side extensions, not over the hardware notch center.
- Keep expanded content below the 38 pt physical-notch area.
- Use `NSScreen.safeAreaInsets` and auxiliary top areas for runtime notch detection when generalizing beyond the local machine.

Future runtime notch calculation:

```swift
notchWidth = screen.frame.width
    - screen.auxiliaryTopLeftArea.width
    - screen.auxiliaryTopRightArea.width

notchHeight = screen.safeAreaInsets.top
```

For non-notch displays, the island should still appear top center, using a conservative synthetic notch reference width so the layout remains stable.

## Out Of Scope For MVP

- Multiple tabs.
- Multiple panes.
- Full Ghostty config compatibility.
- AI assistant.
- Command suggestions.
- SSH profile manager.
- Plugin system.
- iCloud sync.
- Teams or collaboration.
- App Store distribution.
- Full terminal replacement behavior.
- Advanced theming.
- Multi-monitor perfection.
- Perfect fullscreen behavior.

## Implementation Order From Current State

1. Keep the root project/source tree as the implementation target.
2. Add `Terminal/` with shell resolution and PTY session lifecycle.
3. Replace `IslandExpandedView` placeholder content with a terminal container view.
4. Wire terminal focus/input to expanded panel state.
5. Preserve the shell session across collapse/expand.
6. Add the product toggle hotkey separately from the debug color hotkey.
7. Add runtime notch measurement and fallback display behavior.
8. Remove or hide Stage 1 debug color controls before public MVP.

## Acceptance Criteria

The MVP is complete when:

- The app launches and shows the notch-attached collapsed island.
- Hover expands to the preview state without stealing focus.
- Click expands into a compact terminal and accepts keyboard input.
- The user can run real commands in the default shell.
- Escape collapses the island.
- Clicking outside collapses the island.
- Collapsing does not kill the shell session.
- Reopening shows the same shell session and output buffer.
- The island remains top-flush and visually aligned with the notch.
- The app has a product hotkey for toggling the terminal.
- The implementation uses the root `GhostNotch.xcodeproj` and root `GhostNotch/` source tree.

## Documentation References

- `README.md`: top-level project entry point.
- `docs/notch_geometry_research.md`: measured notch geometry and AppKit runtime detection notes.
- `docs/ghostnotch_mvp_spec.md`: this MVP implementation reference.

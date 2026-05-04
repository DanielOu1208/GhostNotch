# NotchTerm MVP Specification

## Project Summary

**NotchTerm** is a native macOS Dynamic-Island-style terminal utility for MacBooks. It shows a small visual indicator near the notch to signal that the app is active, then expands into a tiny, quick-access terminal when the user hovers or clicks.

The app should feel like a lightweight terminal built into the MacBook notch: always available, visually minimal, fast to open, and useful for quick commands.

The MVP should be built as a **native Swift macOS app** and should use **libghostty / ghosttylib as the terminal emulator if possible**.

---

## Product Goal

Create a tiny floating terminal island for macOS that:

- Sits visually near the MacBook notch.
- Shows a small always-visible active indicator.
- Expands on hover or click.
- Provides a quick real terminal session.
- Uses Ghostty’s terminal engine through libghostty if feasible.
- Feels like a Dynamic Island, not a normal terminal window.

The MVP should prioritize speed, polish, and a small footprint over advanced terminal features.

---

## Core Product Concept

The app has two visual states:

### 1. Active Indicator State

A small pill, dot, capsule, or notch-attached indicator appears near the top center of the screen.

This state means:

- The app is running.
- A terminal session is available.
- The app is not currently taking keyboard focus.
- The island is ready to expand.

The indicator should be visually subtle and should not interfere with the menu bar.

Example behavior:

```text
[ small black pill near notch ]
```

### 2. Expanded Island State

When the user hovers over or clicks the indicator, it expands into a small terminal panel.

This state means:

- The terminal becomes visible.
- The terminal accepts keyboard input.
- The user can run quick commands.
- The shell session remains alive after collapse.

Example behavior:

```text
[ notch indicator expands into compact terminal ]
> git status
> npm run dev
> pwd
```

---

## Target User Experience

The ideal flow:

```text
User sees a small active island near the notch.
User hovers or clicks the island.
Island smoothly expands into a small terminal.
User types a quick shell command.
User presses Escape, clicks away, or moves away.
Island collapses back into the active indicator.
The shell session keeps running in the background.
```

The app should feel closer to **Dynamic Island + Raycast quick interaction** than to a full terminal window.

---

## MVP Scope

### In Scope

- Native macOS Swift app.
- Floating Dynamic-Island-style UI.
- Small persistent active indicator.
- Hover-to-expand behavior.
- Click-to-expand behavior.
- Escape-to-collapse behavior.
- Click-outside-to-collapse behavior.
- One persistent terminal session.
- Terminal session remains alive while collapsed.
- Use user’s default shell.
- Integrate libghostty / ghosttylib if possible.
- Minimal settings needed for development/testing.
- Main-display support.
- Basic fallback behavior for non-notch displays.

### Out of Scope

- Multiple terminal tabs.
- Multiple panes.
- AI assistant.
- Command suggestions.
- Full Ghostty config compatibility.
- App Store distribution.
- Advanced theming.
- Multi-monitor perfection.
- Perfect fullscreen behavior.
- iCloud sync.
- Teams/collaboration.
- Plugin system.
- SSH profile manager.
- Custom terminal workflows.
- Full Raycast replacement.

---

## Platform Requirements

### Operating System

Target:

```text
macOS 14 Sonoma or newer
```

Optional:

```text
macOS 13 Ventura support if easy
```

### Hardware

Primary target:

```text
MacBook with notch
```

Fallback target:

```text
Mac desktop or non-notch MacBook
```

On non-notch displays, the island should still appear at the top center of the screen as a floating capsule.

---

## Technical Stack

### App Layer

```text
Language: Swift
UI: SwiftUI + AppKit
Windowing: NSPanel or borderless NSWindow
Terminal Engine: libghostty / ghosttylib
Process Management: PTY-backed shell session
Hotkeys: Native Carbon hotkey API or KeyboardShortcuts package
Settings: UserDefaults for MVP
```

### Why Swift + AppKit/SwiftUI

SwiftUI is good for the visual island UI, but AppKit is needed for:

- Floating windows.
- Borderless panels.
- Window levels.
- Spaces behavior.
- Focus behavior.
- Click-outside handling.
- Precise screen positioning.

Use SwiftUI for views, but AppKit for window and lifecycle control.

---

## Architecture Overview

```text
NotchTerm
├── App Shell
│   ├── AppDelegate
│   ├── Menu bar lifecycle
│   └── Launch behavior
│
├── Island Window System
│   ├── Floating NSPanel / NSWindow
│   ├── Top-center positioning
│   ├── Hover/click expansion
│   ├── Collapse behavior
│   └── Animation controller
│
├── Terminal System
│   ├── TerminalSession
│   ├── PTY process management
│   ├── Default shell detection
│   ├── libghostty integration
│   └── Terminal rendering view
│
├── Input System
│   ├── Keyboard focus handling
│   ├── Mouse hover tracking
│   ├── Click outside detection
│   ├── Escape collapse
│   └── Optional global hotkey
│
└── Settings
    ├── Shell path
    ├── Startup directory
    ├── Island size
    ├── Expand behavior
    └── Debug options
```

---

## Recommended Repository Structure

```text
NotchTerm/
├── NotchTermApp.swift
├── AppDelegate.swift
│
├── Window/
│   ├── IslandPanelController.swift
│   ├── IslandWindow.swift
│   ├── WindowPositioner.swift
│   ├── WindowLevelManager.swift
│   └── OutsideClickMonitor.swift
│
├── UI/
│   ├── IslandRootView.swift
│   ├── IslandIndicatorView.swift
│   ├── IslandExpandedView.swift
│   ├── TerminalContainerView.swift
│   └── StatusGlyphView.swift
│
├── Terminal/
│   ├── TerminalSession.swift
│   ├── PTYProcess.swift
│   ├── ShellResolver.swift
│   ├── GhosttyBridge.swift
│   ├── GhosttyTerminalView.swift
│   └── TerminalSessionState.swift
│
├── Input/
│   ├── HoverController.swift
│   ├── FocusController.swift
│   ├── HotkeyManager.swift
│   └── KeyboardEventRouter.swift
│
├── Settings/
│   ├── AppSettings.swift
│   └── SettingsStore.swift
│
├── Resources/
│   └── Assets.xcassets
│
└── README.md
```

---

## UI States

### State 1: Indicator

The indicator is the default visible state.

Requirements:

- Small, subtle, and centered near the notch.
- Should not look like a normal window.
- Should not take keyboard focus.
- Should not block common menu bar usage.
- Should communicate that the terminal is available.
- Should visually feel attached to the notch.

Possible indicator designs:

```text
Small capsule:
╭────────╮
╰────────╯

Small dot:
●

Tiny terminal glyph:
>_

Thin notch underline:
━━━━
```

Recommended MVP design:

```text
Small rounded black capsule with a tiny terminal glyph or glowing dot.
```

Example:

```text
╭──── >_ ────╮
```

### State 2: Hover Preview

When the user hovers over the indicator:

- The island expands slightly.
- It may show a short preview such as current directory or shell status.
- It should not immediately steal keyboard focus unless the user clicks or starts typing.

Recommended behavior:

```text
Hover → visual expansion only
Click → full terminal focus
```

This avoids annoying accidental focus changes.

### State 3: Expanded Terminal

When the user clicks the indicator:

- The island expands into a small terminal panel.
- The terminal accepts keyboard input.
- The shell is interactive.
- The panel remains compact.

Recommended expanded size:

```text
Width: 520–720 px
Height: 220–320 px
```

The MVP should not try to be a full-screen terminal replacement.

### State 4: Collapsed With Running Session

When the terminal is collapsed:

- The shell process continues running.
- The terminal output buffer is preserved.
- Reopening shows the previous session.
- Long-running commands continue in the background.

Example:

```text
npm run dev
```

If the user collapses the island, the process should continue.

---

## Interaction Requirements

### Expand

The island should expand when:

- User hovers over the indicator.
- User clicks the indicator.

MVP recommendation:

```text
Hover → preview expansion
Click → terminal expansion with focus
```

Optional:

```text
Hover for 300ms → expand fully
```

But this may feel too aggressive. For MVP, use click-to-focus.

### Collapse

The island should collapse when:

- User presses Escape.
- User clicks outside.
- Terminal loses focus, if hide-on-blur is enabled.
- User clicks a close/collapse control.

Default MVP behavior:

```text
Escape collapses.
Click outside collapses.
Hover-out only collapses if terminal is not focused.
```

Do not collapse while the user is actively typing.

### Focus

Collapsed state:

```text
Does not take focus.
```

Hover preview:

```text
Does not take focus.
```

Expanded terminal state:

```text
Takes keyboard focus.
```

Collapse:

```text
Returns focus to the previously active app when possible.
```

### Hotkey

Optional but strongly recommended for MVP.

Default hotkey:

```text
Option + Space
```

Alternative hotkeys:

```text
Control + Space
Option + `
Command + Option + Space
```

Hotkey behavior:

```text
If collapsed → expand and focus terminal.
If expanded → collapse.
```

---

## Terminal Requirements

### Terminal Engine

Preferred:

```text
libghostty / ghosttylib
```

The app should use Ghostty’s terminal engine if the API is stable enough to embed.

The implementation should include a clear abstraction layer so that the UI does not depend directly on libghostty internals.

```swift
protocol TerminalRenderingEngine {
    func start(session: TerminalSession)
    func sendInput(_ input: Data)
    func resize(cols: Int, rows: Int)
    func focus()
    func blur()
}
```

This allows fallback or future replacement if libghostty integration is difficult.

### Shell

Use the user’s default shell.

Default shell detection:

```text
1. Read SHELL environment variable.
2. Fallback to /bin/zsh.
```

The shell session should start in:

```text
User home directory
```

Future setting:

```text
Custom startup directory
```

### Session Persistence

The terminal session must persist while the island is collapsed.

Requirements:

- Do not kill shell on collapse.
- Do not reset terminal buffer on collapse.
- Do not recreate session every time the island expands.
- Provide a debug reset action during development.

### Basic Commands That Should Work

The MVP should support:

```bash
pwd
ls
cd
clear
whoami
date
git status
npm run dev
python3 --version
node --version
```

### Interactive Programs

Nice to have, but not required for early MVP:

```bash
vim
nano
less
top
ssh
```

With libghostty, these should eventually work, but the MVP should first focus on quick command workflows.

---

## libghostty Integration Plan

### Goal

Embed Ghostty’s terminal engine directly into the Swift macOS app.

### Integration Layer

Create a dedicated bridge:

```text
GhosttyBridge.swift
```

Responsibilities:

- Initialize libghostty.
- Create terminal surface.
- Attach terminal to Swift/AppKit view.
- Forward keyboard input.
- Forward mouse input if needed.
- Handle terminal resize.
- Connect terminal to PTY session.
- Render into the island’s terminal view.

### Important Constraint

The rest of the app should not know how libghostty works internally.

The app should talk to:

```text
TerminalSession
TerminalRenderingEngine
TerminalContainerView
```

not directly to libghostty.

### Fallback Strategy

Although the goal is to use libghostty directly, the codebase should allow a temporary fallback renderer if needed.

Fallback renderer:

```text
SimplePTYTextRenderer
```

This fallback is only for development and debugging. The final MVP should attempt to ship with libghostty.

---

## Windowing Requirements

### Window Type

Use either:

```text
NSPanel
```

or:

```text
Borderless NSWindow
```

Recommended first choice:

```text
NSPanel
```

because it is better suited for floating utility UI.

### Window Style

Requirements:

```text
- Borderless
- Transparent background
- Rounded island content
- No title bar
- No traffic light buttons
- Non-activating when collapsed
- Activating when expanded terminal needs focus
```

### Window Level

Suggested:

```swift
panel.level = .floating
```

Potential alternatives to test:

```swift
.statusBar
.popUpMenu
.mainMenu
```

Avoid overly aggressive window levels unless necessary.

### Spaces Behavior

Suggested collection behavior:

```swift
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .stationary
]
```

MVP goal:

- Works on normal desktop.
- Mostly works across Spaces.
- Does not need perfect fullscreen behavior yet.

### Main Display Only

For MVP:

```text
Show island on the main display only.
```

Later:

```text
Follow active display.
Support multi-monitor positioning.
Allow user to choose display.
```

---

## Positioning Requirements

### Notch-Aware Positioning

MVP positioning:

```text
Horizontally centered on main display.
Vertically near the top safe area/menu bar.
```

Do not attempt complex hardware notch detection in the first version.

Suggested positioning logic:

```text
x = screen.midX - islandWidth / 2
y = screen.maxY - menuBarHeight - topOffset
```

The app should expose debug constants:

```text
indicatorWidth
indicatorHeight
expandedWidth
expandedHeight
topOffset
```

This makes it easy to tune positioning manually.

### Non-Notch Displays

If no notch is present or detection is unavailable:

```text
Still show the island at top center.
```

The design should still look intentional.

---

## Visual Design

### Style Direction

The MVP should look like:

```text
Apple Dynamic Island
+
Tiny terminal
+
Raycast-level polish
```

### Visual Attributes

```text
Background: near-black
Corner radius: very large / pill-shaped
Shadow: soft but subtle
Border: optional thin translucent border
Text: monospaced
Terminal prompt: compact
Animation: springy but fast
```

### Indicator Design

Recommended:

```text
Small black capsule with a tiny >_ glyph.
```

Collapsed size:

```text
Width: 72–120 px
Height: 24–32 px
```

Expanded size:

```text
Width: 520–720 px
Height: 220–320 px
```

### Animation

Requirements:

- Smooth expansion from indicator to terminal.
- Fast enough to feel instant.
- No janky resize.
- No full-window flicker.

Recommended:

```text
Expansion duration: 120–180ms
Collapse duration: 100–150ms
```

---

## MVP User Stories

### Story 1: See Active Indicator

As a user, I want to see a small island near the notch so that I know NotchTerm is running.

Acceptance criteria:

```text
Given the app is launched
When I look near the notch
Then I see a small subtle terminal indicator
And it does not interrupt my current app
```

### Story 2: Expand on Hover

As a user, I want the island to react when I hover over it so that it feels alive and discoverable.

Acceptance criteria:

```text
Given the indicator is visible
When I move my cursor over it
Then it expands slightly or shows a preview
And it does not steal keyboard focus
```

### Story 3: Open Terminal on Click

As a user, I want to click the island to open a terminal so that I can run a quick command.

Acceptance criteria:

```text
Given the indicator is visible
When I click it
Then it expands into a compact terminal
And the terminal accepts keyboard input
```

### Story 4: Run Command

As a user, I want to run shell commands from the island terminal.

Acceptance criteria:

```text
Given the terminal is expanded
When I type "pwd" and press Enter
Then I see the command output
```

### Story 5: Collapse Terminal

As a user, I want to quickly dismiss the terminal.

Acceptance criteria:

```text
Given the terminal is expanded
When I press Escape
Then the island collapses back to the active indicator
```

### Story 6: Preserve Session

As a user, I want the terminal session to persist after collapse.

Acceptance criteria:

```text
Given I have an active terminal session
When I collapse the island
And reopen it later
Then the previous shell session and output are still there
```

---

## Development Stages

## Stage 1: Native Island Shell

### Goal

Build the floating Dynamic-Island-style UI without a terminal.

### Features

- Native Swift macOS app.
- Borderless floating panel.
- Active indicator.
- Hover expansion.
- Click expansion.
- Escape collapse.
- Click-outside collapse.
- Basic animation.

### Success Criteria

```text
The app feels like a real notch island even before terminal integration.
```

---

## Stage 2: Terminal Container View

### Goal

Create the terminal UI container that will eventually host libghostty.

### Features

- Expanded panel layout.
- Terminal header/status area.
- Terminal content area.
- Placeholder terminal view.
- Focus state visuals.
- Scroll region placeholder.

### Success Criteria

```text
The expanded island looks like a tiny terminal.
The view is ready to host libghostty.
```

---

## Stage 3: PTY Session Layer

### Goal

Create the shell process and PTY lifecycle.

### Features

- Start default shell.
- Keep shell alive.
- Send input to shell.
- Read output from shell.
- Resize PTY when island resizes.
- Stop shell on app quit.

### Success Criteria

```text
A shell process can run independently from the UI.
The shell does not die when the island collapses.
```

---

## Stage 4: libghostty Rendering Integration

### Goal

Render the terminal using libghostty.

### Features

- Initialize Ghostty terminal engine.
- Embed rendering surface in Swift/AppKit view.
- Connect PTY output to terminal engine.
- Send keyboard input through terminal engine.
- Support resize.
- Support basic ANSI rendering.
- Support copy/paste if feasible.

### Success Criteria

```text
The terminal behaves like a real Ghostty-backed terminal inside the island.
Basic shell commands work.
ANSI colors render correctly.
```

---

## Stage 5: MVP Polish

### Goal

Make the app usable as a daily quick terminal.

### Features

- Menu bar icon.
- Quit action.
- Reset terminal action.
- Configurable hotkey.
- Choose shell path.
- Launch at login if easy.
- Debug positioning settings.
- Basic error handling.

### Success Criteria

```text
The user can keep NotchTerm running throughout the day and use it for quick commands.
```

---

## Error Handling

### libghostty Fails to Initialize

Show a small error state inside the expanded island:

```text
Terminal engine failed to start.
Check libghostty integration.
```

Provide a debug action:

```text
Restart Terminal Engine
```

### Shell Fails to Start

Show:

```text
Could not start shell.
Using fallback: /bin/zsh
```

If fallback also fails:

```text
Shell unavailable.
```

### PTY Process Exits

Show:

```text
Shell exited.
Click to restart.
```

---

## Settings for MVP

Minimal settings:

```text
- Hotkey
- Shell path
- Startup directory
- Expand on hover: on/off
- Hide on blur: on/off
- Launch at login: on/off
```

Settings can be stored in:

```text
UserDefaults
```

No database is needed.

---

## App Menu Bar Behavior

The app should run as a lightweight utility.

Menu bar options:

```text
Open NotchTerm
Reset Terminal Session
Settings
Quit
```

MVP can show a simple menu bar icon even if the island is the main UI.

---

## Privacy and Security

The app runs a local shell, so it should be careful about:

- Not logging terminal contents.
- Not uploading command history.
- Not storing shell output unless explicitly added later.
- Avoiding unnecessary permissions.
- Avoiding accessibility permissions unless absolutely needed.

MVP should not require:

```text
Accessibility permissions
Screen recording permissions
Network permissions beyond what shell commands themselves use
```

---

## Key Risks

### Risk 1: libghostty API Complexity

libghostty may be harder to embed than expected.

Mitigation:

```text
Keep GhosttyBridge isolated.
Build PTY/session logic separately.
Allow a development fallback renderer.
```

### Risk 2: macOS Focus Behavior

Floating terminal windows can accidentally steal focus or fail to receive input.

Mitigation:

```text
Separate collapsed and expanded focus behavior.
Use non-activating behavior only while collapsed.
Allow activation when terminal is expanded.
```

### Risk 3: Fullscreen and Spaces Issues

The island may behave inconsistently in fullscreen apps or across Spaces.

Mitigation:

```text
Treat fullscreen behavior as post-MVP polish.
Support normal desktop well first.
```

### Risk 4: Notch Positioning Differences

Different MacBook models have different notch/menu bar geometry.

Mitigation:

```text
Use top-center positioning first.
Expose debug offset constants.
Add model-specific polish later.
```

---

## MVP Acceptance Criteria

The MVP is complete when:

```text
1. App launches as a native macOS utility.
2. A small island indicator appears near the notch.
3. Hovering over the indicator gives a visual expansion/preview.
4. Clicking the indicator opens a compact terminal.
5. The terminal is backed by libghostty if feasible.
6. The terminal can run basic shell commands.
7. Pressing Escape collapses the terminal.
8. Clicking outside collapses the terminal.
9. The shell session persists after collapse.
10. The app can be quit cleanly from the menu bar.
```

---

## First Build Milestone

The first milestone should not include a real terminal.

Build this first:

```text
Native macOS app
Floating island indicator
Hover animation
Click expansion
Escape collapse
Click-outside collapse
Menu bar quit item
```

Once this feels good, add terminal functionality.

---

## Suggested First Agent Task

```markdown
Build the Stage 1 native macOS shell for NotchTerm.

Requirements:
- Use Swift and SwiftUI with AppKit where needed.
- Create a borderless floating NSPanel positioned at the top center of the main display.
- The panel should show a small rounded black capsule indicator by default.
- On hover, the capsule should subtly expand.
- On click, the panel should expand into a larger rounded rectangle.
- Pressing Escape should collapse it.
- Clicking outside should collapse it.
- The collapsed state should not steal keyboard focus.
- The expanded state should be able to become key/focused.
- Add a menu bar item with Quit.
- Do not implement the terminal yet.
```

---

## Suggested Second Agent Task

```markdown
Add a TerminalSession abstraction and PTY process layer.

Requirements:
- Create TerminalSession, PTYProcess, and ShellResolver classes.
- Resolve the user's default shell from the SHELL environment variable.
- Fallback to /bin/zsh.
- Start a persistent shell process.
- Keep the shell alive while the island is collapsed.
- Provide methods to send input, receive output, resize, restart, and terminate.
- Do not connect to libghostty yet.
```

---

## Suggested Third Agent Task

```markdown
Integrate libghostty as the terminal rendering engine.

Requirements:
- Create GhosttyBridge and GhosttyTerminalView.
- Initialize libghostty.
- Embed the terminal rendering surface into the expanded island.
- Connect PTY output to libghostty.
- Forward keyboard input from the terminal view.
- Handle terminal resizing.
- Support basic ANSI color rendering.
- Keep the integration isolated behind TerminalRenderingEngine.
```

---

## Future Features After MVP

Possible future directions:

```text
- Multiple sessions
- Quick command palette
- AI command explanation
- SSH profiles
- Per-project terminals
- Git status indicator in collapsed island
- Long-running command status
- Notification when command completes
- Themed terminal presets
- Custom island positioning
- Multi-monitor support
- Fullscreen app support
- Plugin system
```

---

## Product Philosophy

NotchTerm should not try to replace Ghostty, iTerm, Terminal.app, or Warp.

It should be:

```text
Tiny
Fast
Always available
Beautiful
Focused on quick terminal interactions
```

The app wins if users instinctively use it for small commands instead of opening a full terminal window.

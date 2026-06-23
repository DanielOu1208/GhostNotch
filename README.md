# GhostNotch

GhostNotch is an experimental macOS app that turns the MacBook notch into a tiny terminal island.

It sits flush with the top of the built-in display, looks like a small extension of the hardware notch, and expands into a compact terminal when you need a quick shell. It is meant for short, lightweight terminal interactions, not as a replacement for a full terminal app.

![GhostNotch expanded terminal island](docs/image2.webp)

## What You Can Do

- Press `Option+Space` to expand or collapse the terminal island.
- Click the island to focus the terminal.
- Run commands in your default shell.
- Collapse the island without killing the shell session.
- Reopen it later and continue from the same session.
- Launch Codex or Claude from the hover controls.
- Save up to three directory presets and launch an agent inside one of them.
- Open native Settings to choose visible agents and manage directory presets.
- Install optional Codex and Claude hooks so the island can show when an agent is working or needs attention.
- Use keyboard input, paste, terminal resize, scrollback, selection, and common terminal UI programs while the renderer continues to improve.

GhostNotch has three visible states:

- **Collapsed:** a subtle active notch extension.
- **Hover:** a larger preview state that does not take keyboard focus.
- **Expanded:** a compact terminal panel with keyboard focus.

## Project Status

GhostNotch is a prototype moving toward a `v0.1.0` public preview. The v0 release path targets a downloadable GitHub DMG, but that DMG is self-signed and not notarized.

That means macOS Gatekeeper may warn that the app is from an unidentified developer. Gatekeeper is the macOS safety check that runs when you open downloaded apps. This v0 path is meant to make testing easier, not to present GhostNotch as a normal trusted production app yet.

Ready today:

- Native macOS notch-attached panel.
- Persistent default-shell PTY session.
- Hover controls with Codex and Claude launcher buttons.
- Directory presets for launching agents inside saved folders.
- Native Settings UI for visible agents and directory presets.
- Optional Codex and Claude shell hooks for working/attention indicators.
- Ghostty-backed terminal parsing/state through a vendored `libghostty-vt` artifact.
- App-owned AppKit/CoreText terminal grid renderer.
- ANSI styles, cursor movement, alternate-screen support, primary-screen scrollback, grapheme-aware snapshots, wide-cell metadata, and text selection/copy.
- Runtime notch measurement on notch displays, with a synthetic fallback on non-notch displays.
- Stable v0 app identity metadata, version fields, and app icon.

Not ready yet:

- A published GitHub Release.
- Auto-update, Homebrew, or App Store distribution.
- Developer ID signing or notarization.
- Full Ghostty renderer, configuration, shell integration, or terminal-app parity.
- Final manual acceptance across real terminal programs after the latest renderer hardening.

## Try It Locally

Requirements:

- macOS
- Xcode
- A local checkout of this repository

Open the root project in Xcode:

```text
GhostNotch.xcodeproj
```

Then run the `GhostNotch` scheme.

You can also build from the command line:

```sh
xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Debug build
```

Running from Xcode still uses local development build settings. For a distributable preview build, use the local DMG packaging script below.

## Package a Local DMG

The v0 packaging script builds a Release app, signs it with a local self-signed certificate, creates a DMG with an `/Applications` shortcut, and writes a SHA-256 checksum.

Before running it, create a local code-signing certificate in Keychain Access named:

```text
GhostNotch Self-Signed Release
```

Then run:

```sh
scripts/package-dmg.sh
```

Outputs are written to `dist/`, which is intentionally ignored by git.

## How It Works

GhostNotch is a native Swift macOS app built with AppKit, SwiftUI, and a PTY-backed terminal session.

At a high level:

1. `AppDelegate` creates the menu bar item and notch island panel.
2. `IslandPanelController` owns the floating panel, state transitions, focus behavior, and the single terminal session.
3. `PTYProcess` starts the user's shell in a pseudo-terminal.
4. `TerminalSession` keeps the PTY process alive and exposes input, output, resize, startup, and lifecycle state.
5. `GhosttyTerminalEngine` feeds PTY output into a Ghostty-backed terminal core.
6. The terminal grid UI draws the resulting snapshot through GhostNotch-owned AppKit/CoreText renderer modules.

The important boundary: GhostNotch uses Ghostty's VT/render-state layer. It does not embed Ghostty's full renderer, configuration system, shell integration, or terminal application behavior.

## Repository Layout

```text
GhostNotch/
├── GhostNotch/                 # App source
│   ├── Terminal/               # PTY, shell session, Ghostty VT bridge, input, render model
│   ├── UI/                     # Island views and modular terminal grid renderer
│   └── Window/                 # NSPanel, positioning, outside-click behavior
├── GhostNotchTests/            # Unit tests
├── docs/                       # Public contributor docs and archived planning notes
├── scripts/                    # Vendor/build helper scripts
├── vendor/ghostty-vt/          # Pinned Ghostty VT artifact and headers
└── GhostNotch.xcodeproj        # Canonical Xcode project
```

Use the root `GhostNotch.xcodeproj` and root `GhostNotch/` source tree.

## Documentation

- [Docs index](docs/README.md) is the best starting point for contributors.
- [Architecture](docs/architecture.md) explains the current app structure and Ghostty boundary.
- [Testing](docs/testing.md) covers build, automated tests, and manual terminal acceptance.
- [v0.1.0 release notes](docs/releases/v0.1.0.md) summarize the planned public preview release.
- [v0 DMG release tracking](docs/v0-dmg-release-tracking.md) tracks the self-signed DMG release path.
- [Agent indicator hooks](docs/agent-indicator-hooks.md) explains Codex and Claude hook setup and indicator state mapping.
- [MacBook notch geometry](docs/notch-geometry.md) records the notch sizing and positioning assumptions.
- [Xcode debugging](docs/xcode-debugging.md) covers LLDB task-port attach failures and terminal startup hangs.
- [Ghostty VT vendor notes](vendor/ghostty-vt/README.md) describe the vendored terminal artifact.

## License

GhostNotch is available under the [MIT License](LICENSE).

## Contributing

The best contribution path is to start from the docs index, then keep changes small and testable.

Useful areas:

- Renderer acceptance testing in `less`, `vim` or `nano`, and `top`.
- Alternate-screen scrolling and collapse/reopen viewport stability.
- Font, glyph, color, cursor, and selection polish.
- Startup/debugging hardening around shell launch and Xcode attach behavior.
- Shell identity, terminfo, and shell integration design.
- Runtime notch measurement across MacBook models and external displays.
- Keeping the Ghostty boundary narrow, explicit, and replaceable.

When changing terminal behavior, preserve the architecture boundary:

- Panel and SwiftUI code should not depend directly on Ghostty C types.
- `GhosttyVTBridge` should isolate unstable C API details.
- `GhosttyTerminalCore`, `GhosttyTerminalEngine`, and `TerminalRenderSnapshot` should remain the stable app-facing terminal boundary.
- The terminal grid should stay decomposed into focused rendering, typography, decoration, pixel-grid, and AppKit key-mapping modules.

## Direction

GhostNotch is exploring a focused idea: a terminal that feels built into the MacBook notch instead of floating as another desktop window.

The near-term goal is a reliable MVP for quick commands and compact shell workflows. Broader terminal-app features like tabs, panes, profiles, plugin systems, advanced theming, and full Ghostty compatibility are intentionally out of scope for now.

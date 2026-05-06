# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)
- [MacBook notch geometry research](docs/notch_geometry_research.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest notch-integrated island shell, native PTY-backed terminal session module, and Ghostty-backed terminal rendering boundary.

The expanded island now starts a persistent default-shell PTY session on first open, renders terminal output through a `libghostty-vt`-backed grid surface, accepts Ghostty-encoded keyboard input plus paste, supports primary-screen scrollback and text selection, and keeps the session alive while collapsed. This is a Ghostty-backed notch terminal surface, not a full Ghostty-equivalent renderer or shell environment yet.

The next implementation stage is terminal fidelity: improve text rendering correctness beyond one-codepoint cell drawing, add shell/terminfo integration closer to Ghostty's runtime environment, then continue TUI/editor hardening on top of the vendored Ghostty VT bridge. Runtime notch measurement/fallback behavior and removal of debug-only notch color controls are still required before a public MVP build.

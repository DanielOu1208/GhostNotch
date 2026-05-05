# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)
- [MacBook notch geometry research](docs/notch_geometry_research.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest notch-integrated island shell and native PTY-backed terminal session module.

The expanded island now starts a persistent default-shell PTY session on first open, renders recent terminal output, accepts keyboard input and paste, and keeps the session alive while collapsed.

The next implementation stage is product polish around the terminal shell: add the product toggle hotkey, improve terminal rendering beyond raw PTY text, and generalize runtime notch measurement while preserving the current geometry and focus behavior.

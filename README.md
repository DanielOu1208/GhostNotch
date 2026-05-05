# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)
- [MacBook notch geometry research](docs/notch_geometry_research.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest notch-integrated island shell, native PTY-backed terminal session module, and Ghostty-style terminal rendering boundary.

The expanded island now starts a persistent default-shell PTY session on first open, renders terminal output through a grid-based VT surface, accepts keyboard input and paste, and keeps the session alive while collapsed.

The next implementation stage is product polish around the terminal shell: swap the compatibility VT core for a built `libghostty-vt` artifact, generalize runtime notch measurement, and remove debug-only notch color controls before a public build.

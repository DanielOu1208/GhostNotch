# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)
- [MacBook notch geometry research](docs/notch_geometry_research.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest notch-integrated island shell, native PTY-backed terminal session module, and Ghostty-backed terminal rendering boundary.

The expanded island now starts a persistent default-shell PTY session on first open, renders terminal output through a `libghostty-vt`-backed grid surface, preserves Ghostty grapheme clusters and wide-cell spacer metadata in the render model, accepts Ghostty-encoded keyboard input plus paste, supports primary-screen scrollback and text selection, and keeps the session alive while collapsed. This is a Ghostty-backed notch terminal surface, not a full Ghostty-equivalent renderer or shell environment yet.

The next implementation stage is tracked in the MVP spec as concrete renderer, shell-integration, and Ghostty/libghostty-alignment work packages. The highest-priority work is manual TUI/editor renderer acceptance, bracketed-paste/full-screen paste behavior, font/color/mouse polish, then terminal identity, terminfo policy, shell integration resources, and comparison fixtures that keep a future fuller Ghostty renderer path replaceable.

# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)
- [MacBook notch geometry research](docs/notch_geometry_research.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest notch-integrated island shell, native PTY-backed terminal session module, and Ghostty-backed terminal rendering boundary.

The expanded island now starts a persistent default-shell PTY session on first open, renders terminal output through a `libghostty-vt`-backed grid surface, preserves Ghostty grapheme clusters and wide-cell spacer metadata in the render model, accepts Ghostty-encoded keyboard input plus paste, supports primary-screen scrollback and text selection, and keeps the session alive while collapsed. This is a Ghostty-backed notch terminal surface, not a full Ghostty-equivalent renderer or shell environment yet.

The next implementation stage is renderer fidelity: keep the AppKit grid renderer, but use CoreText-backed drawing, deterministic installed developer-font preference, fallback-font behavior, and manual TUI/editor stress validation on top of the vendored Ghostty VT bridge. Shell integration follows after that with terminal metadata, terminfo policy, shell integration resource paths, and common-shell setup guidance that does not mutate user dotfiles silently.

# GhostNotch

GhostNotch is a native macOS Dynamic-Island-style terminal utility.

The current product and implementation reference is:

- [MVP specification](docs/ghostnotch_mvp_spec.md)

Use the root `GhostNotch.xcodeproj` as the canonical project. It builds the root `GhostNotch/` source tree, which contains the latest Stage 1 notch-integrated island shell.

The next implementation stage is terminal integration: replace the placeholder expanded view with one persistent default-shell session while preserving the current notch geometry and focus behavior.

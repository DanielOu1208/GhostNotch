# Ghostty VT Vendor Boundary

GhostNotch targets Ghostty's `libghostty-vt` API for terminal state and input encoding, but this repository does not commit a built Ghostty binary artifact yet.

Current local state:

- `/Applications/Ghostty.app` contains the Ghostty application executable, docs, terminfo, and Sparkle framework.
- It does not expose a reusable `libghostty-vt` static library, dynamic library, framework, or header bundle.
- `zig` is not installed in the current development environment, so the library cannot be built in-place without adding that toolchain.

Pinned upstream API reference:

- Repository: `https://github.com/ghostty-org/ghostty`
- Header boundary: `include/ghostty/vt.h`
- API status: work in progress and not stable.

Intended artifact layout once built:

```text
vendor/ghostty-vt/
├── README.md
├── GhosttyVT.xcframework/
└── include/
    └── ghostty/
        └── vt.h
```

Until the binary artifact is added, `GhosttyTerminalCore` provides a Swift compatibility implementation behind the same app-facing wrapper. Keep all direct Ghostty C calls isolated to that wrapper when replacing the compatibility core with the real library.

# Ghostty VT Vendor Boundary

GhostNotch vendors a built Ghostty `libghostty-vt` artifact for terminal state, render snapshots, and input encoding helpers. The app links `GhosttyVT.xcframework` through the Xcode project and keeps direct C API usage behind `GhosttyVTBridge`.

Build command:

```sh
./scripts/build-ghostty-vt.sh
```

The script downloads the pinned Ghostty source tarball and uses Zig 0.15.2 to build `libghostty-vt`. By default it uses Ghostty's `tip` source tarball because Ghostty 1.3.1's `libghostty-vt` exposes parser and input helpers, but not the terminal/grid state API GhostNotch needs.

On macOS 26/Tahoe, prefer Homebrew's `zig@0.15` bottle because it is built for the current host:

```sh
brew install zig@0.15
./scripts/build-ghostty-vt.sh
```

You can also point the script at any compatible Zig 0.15.2 executable:

```sh
GHOSTTY_ZIG=/path/to/zig ./scripts/build-ghostty-vt.sh
```

Current local state:

- `/Applications/Ghostty.app` contains the Ghostty application executable, docs, terminfo, and Sparkle framework.
- It does not expose a reusable `libghostty-vt` static library, dynamic library, framework, or header bundle.
- `zig` is not required globally; `scripts/build-ghostty-vt.sh` prefers Homebrew `zig@0.15` when present and otherwise downloads the pinned Zig toolchain locally.

Pinned upstream API reference:

- Repository: `https://github.com/ghostty-org/ghostty`
- Header boundary: `include/ghostty/vt.h`
- API status: work in progress and not stable.

Artifact layout:

```text
vendor/ghostty-vt/
├── README.md
├── VERSION
├── GhosttyVT.xcframework/        # linked by the app and test targets
├── lib/
│   └── libghostty-vt*.dylib      # fallback for Ghostty 1.3.1-style source
└── include/
    └── ghostty/
        └── vt.h
```

`GhosttyTerminalCore` is the Swift app-facing wrapper. Keep direct Ghostty C calls isolated to `GhosttyVTBridge` so future upstream API churn stays contained to the vendor boundary and wrapper.

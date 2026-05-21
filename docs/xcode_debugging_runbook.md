# Xcode Debugging Runbook

This note covers GhostNotch failures where Xcode or LLDB prints a message like:

```text
Unable to obtain a task name port right for pid ...: (os/kern) failure (0x5)
```

That message is usually a debugger attach/signing problem, not a terminal-renderer failure. It means LLDB/debugserver could not get the app process task port.

## Quick Checks

Confirm the canonical project and scheme:

```sh
xcodebuild -list -project GhostNotch.xcodeproj
```

Inspect the current Debug build settings:

```sh
xcodebuild -showBuildSettings \
  -project GhostNotch.xcodeproj \
  -scheme GhostNotch \
  -configuration Debug | rg 'CODE_SIGN|ENTITLEMENTS|DEPLOYMENT_POSTPROCESSING|HARDENED|RUNTIME_EXCEPTION'
```

Inspect the built app entitlements after a Debug build:

```sh
codesign -d --entitlements :- \
  ~/Library/Developer/Xcode/DerivedData/GhostNotch-*/Build/Products/Debug/GhostNotch.app
```

For debugger attach to work reliably on macOS Debug builds, the effective app entitlement should include:

```xml
<key>com.apple.security.get-task-allow</key>
<true/>
```

The checked-in project intentionally stays team-agnostic and does not commit a personal Apple development team.

## Build Settings To Inspect

- `CODE_SIGNING_ALLOWED`
- `CODE_SIGN_STYLE`
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`
- `DEPLOYMENT_POSTPROCESSING`
- `ENABLE_HARDENED_RUNTIME`
- `RUNTIME_EXCEPTION_DEBUGGING_TOOL`
- Scheme setting: `Run > Info > Debug executable`

If the app is ad-hoc or linker-signed and has no `com.apple.security.get-task-allow` entitlement, LLDB can fail with the task-port error.

## Local Remediation

Use these as local machine settings unless the team decides to add a shared signing setup later:

1. In Xcode, open the `GhostNotch` target signing settings.
2. Use a local Apple Development identity/team for Debug.
3. Keep Release/distribution signing separate from this local Debug setup.
4. Confirm the built app has `com.apple.security.get-task-allow`.
5. If Xcode remains wedged after a force quit, clean the build folder, quit Xcode, and relaunch before retrying.

## Terminal Startup Hangs

GhostNotch launches the user's resolved shell from `SHELL`. Slow or blocking shell startup files can delay the first prompt. The app now tracks terminal phases separately:

- `starting`: the PTY process launched, but no output has arrived yet.
- `running`: terminal output arrived and the shell is responsive enough to render.
- `failed`: startup timed out or the session hit a terminal error.
- `stopped`: no terminal process is active.

If startup times out, the UI shows an error instead of staying on `Starting shell...` indefinitely. Restarting the terminal starts a fresh PTY session.

# GhostNotch v0 DMG Release Tracking

This document tracks the work needed to ship GhostNotch as a downloadable
GitHub v0 public preview DMG.

Current target: `v0.1.0`

Release model: manual-first, self-signed, not notarized, published as a GitHub
pre-release.

## Release Decision

For v0, GhostNotch should ship a downloadable DMG that users can mount and copy
into `/Applications`, but it should not claim to be a normal trusted macOS
release yet.

The conventional public macOS distribution path outside the Mac App Store is:

1. Sign the app with a Developer ID certificate.
2. Enable hardened runtime.
3. Notarize the app or DMG with Apple.
4. Staple the notarization ticket.
5. Publish the DMG as the release asset.

That path requires Apple Developer Program membership. Apple currently lists
the Apple Developer Program at `99 USD` per membership year, with local-currency
pricing where available.

For this v0, we are intentionally not enrolling yet. The release should use
self-signing only. That is useful for creating a repeatable local build and
catching signature problems, but it does not make the app trusted by other Macs.

## Plain Terms

- `DMG`: A macOS disk image. Users open it, then usually drag the app into
  `/Applications`.
- `Code signing`: A cryptographic signature attached to an app so macOS can
  detect whether the app changed after signing.
- `Self-signed`: Signed with a local certificate that macOS does not trust on
  other users' machines by default.
- `Developer ID`: Apple's certificate type for apps distributed outside the Mac
  App Store.
- `Notarization`: Apple's automated scan and approval process for Developer
  ID-distributed macOS software.
- `Hardened runtime`: A macOS security mode required for notarization.
- `Gatekeeper`: The macOS feature that warns about or blocks apps from
  unidentified developers.
- `Quarantine`: Metadata macOS adds to downloaded files. Quarantined apps are
  checked by Gatekeeper on first launch.

## Current Repo State

Last reviewed: 2026-06-22.

Current high-level status:

- `main` is the release branch candidate.
- The repo is already public on GitHub.
- There are no Git tags and no GitHub Releases yet.
- Automated tests and Release builds have passed recently on this checkout.
- The hover-clearance fix is included in the v0 scope baseline.
- The app has stable v0 bundle identity metadata, version fields, and an app
  icon.
- The repo has a manual self-signed DMG packaging script at
  `scripts/package-dmg.sh`.
- The app still does not have Developer ID signing, notarization, auto-update,
  Homebrew, or App Store distribution.

Known release gaps before publishing:

- No `v0.1.0` Git tag yet.
- No GitHub Release yet.
- The self-signed release certificate still needs to exist locally before
  running `scripts/package-dmg.sh`.
- The generated DMG still needs the packaging verification and manual app
  acceptance pass.
- The exact Gatekeeper warning from a browser-downloaded DMG still needs to be
  recorded in the GitHub Release notes.
- Xcode project signing remains disabled for normal local builds; the packaging
  script applies the v0 self-signature with hardened runtime signing options.

## Track 1: Freeze v0 Scope

Goal: Decide exactly what code will be included in `v0.1.0`.

Recommended work:

- Keep the committed notch hover clearance fix in the v0 baseline.
- Keep v0 focused on the current usable app: notch-attached terminal, hover
  controls, Codex/Claude launch buttons, directory presets, and existing
  terminal rendering baseline.
- Do not add Sparkle auto-update, Homebrew, App Store distribution, or full
  notarization work to v0.
- Keep GitHub Releases as the only v0 distribution channel.

Definition of done:

- `git status --short --branch` is clean except for intentional release-doc or
  packaging changes.
- The commit to tag is known.
- Any intentionally excluded work is preserved on another branch or documented.

Suggested commands:

```sh
git status --short --branch
git log --oneline --decorate -n 12
git diff --stat
```

## Track 2: App Identity

Goal: Give the app stable identity metadata before packaging it.

Recommended work:

- Replace `com.ghostnotch.local` with a stable bundle identifier.
- Add explicit version fields:
  - `MARKETING_VERSION = 0.1.0`
  - `CURRENT_PROJECT_VERSION = 1`
- Add an app icon set to `GhostNotch/Resources/Assets.xcassets`.
- Keep the minimum macOS deployment target at `14.0` unless there is a tested
  reason to lower it.

Recommended bundle ID:

```text
com.danielou.GhostNotch
```

Why this matters:

- Bundle ID is the app's stable identity for macOS preferences, signing,
  updates, crash logs, and future notarization.
- Version fields make the DMG, release notes, and app metadata line up.
- An app icon is visible in Finder, `/Applications`, the Dock, and warning
  dialogs.

Definition of done:

- Release app Info.plist shows the expected bundle ID and version.
- Finder shows a real app icon.
- `xcodebuild -configuration Release build` still succeeds.

Useful checks:

```sh
xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Release build
plutil -p /path/to/GhostNotch.app/Contents/Info.plist | rg 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion'
```

## Track 3: Public Docs

Goal: Make the repo understandable to a user arriving from GitHub Releases.

Recommended work:

- Update `README.md` project status:
  - DMG release is planned for v0.
  - v0 is a public preview.
  - v0 DMG is self-signed and not notarized.
  - Users should expect macOS Gatekeeper friction.
- Update the feature list to include:
  - hover agent launcher buttons,
  - directory presets,
  - native Settings UI,
  - Codex and Claude hook indicator support.
- Add `docs/releases/v0.1.0.md` before tagging.
- Add or choose a `LICENSE`.

Recommended license:

```text
MIT
```

MIT is a conventional default for permissive open source. It lets others use,
modify, and redistribute the code with attribution and without much legal
friction. If you want stronger copyleft requirements, choose GPL instead; if you
want to keep the project source-visible but restrict reuse, do not use MIT.

Definition of done:

- README no longer says settings UI is missing.
- README explains self-signed DMG limitations plainly.
- Release notes list features, requirements, install steps, known limitations,
  and verification notes.
- License exists and GitHub detects it.

## Track 4: Self-Signed DMG Packaging

Goal: Produce a repeatable `GhostNotch-v0.1.0.dmg` locally.

Recommended work:

- Use the manual packaging script at `scripts/package-dmg.sh`.
- Build Release into a clean `dist/` staging folder.
- Self-sign the `.app` with a local certificate.
- Create a DMG containing:
  - `GhostNotch.app`
  - an `/Applications` shortcut
- Self-sign the DMG.
- Generate a SHA-256 checksum file.

DMG tool:

```text
hdiutil
```

Reason: It is built into macOS and avoids adding a third-party packaging
dependency for v0. The resulting DMG is plain, but still contains the app and
an `/Applications` shortcut.

Self-signing setup:

1. Open Keychain Access.
2. Create a local certificate named `GhostNotch Self-Signed Release`.
3. Use the certificate for code signing.

Suggested app signing command:

```sh
codesign --force --deep --options runtime --timestamp=none --sign "GhostNotch Self-Signed Release" dist/GhostNotch.app
```

Important: `--options runtime` enables hardened runtime in the signature. This
does not notarize the app. It does make the local signing path closer to the
future Developer ID path.

Suggested checksum command:

```sh
shasum -a 256 dist/GhostNotch-v0.1.0.dmg > dist/GhostNotch-v0.1.0.dmg.sha256
```

Repeatable script command:

```sh
scripts/package-dmg.sh
```

Definition of done:

- `dist/GhostNotch-v0.1.0.dmg` exists.
- `dist/GhostNotch-v0.1.0.dmg.sha256` exists.
- The DMG mounts.
- The DMG shows `GhostNotch.app` and an `/Applications` shortcut.
- The copied app launches on the build machine.

## Track 5: Verification

Goal: Prove the v0 build is not obviously broken before publishing it.

Required automated checks:

```sh
git diff --check
python3 scripts/install-agent-hooks.py self-test
xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'
xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Release build
```

Required packaging checks:

```sh
codesign --verify --deep --strict --verbose=2 dist/GhostNotch.app
hdiutil verify dist/GhostNotch-v0.1.0.dmg
shasum -a 256 -c dist/GhostNotch-v0.1.0.dmg.sha256
```

Expected `spctl` result for v0:

```text
Self-signed/non-Developer-ID builds may be rejected or reported as from an unidentified developer.
```

Do not treat that as a packaging failure for v0. Do treat it as a release-notes
requirement.

Manual app checks:

- Open the app from the copied `/Applications/GhostNotch.app`.
- Confirm collapsed island appears on the built-in display.
- Confirm hover state appears and does not steal keyboard focus.
- Confirm `Option+Space` expands and collapses the terminal.
- Run a simple shell command.
- Confirm collapse/reopen preserves the shell session.
- Confirm Settings opens and directory presets persist.
- Confirm Codex and Claude hover buttons still use the configured launch flow.
- Run the manual terminal checks from `docs/testing.md` for renderer-sensitive
  changes.

Manual Gatekeeper check:

- Download the DMG from a browser or host it locally and download it through
  Safari.
- Mount the downloaded DMG.
- Copy the app to `/Applications`.
- Try launching it.
- Record the exact warning/error users will see.
- Mirror that wording in the release notes.

## Track 6: GitHub Release

Goal: Publish the v0 DMG as a GitHub pre-release.

Recommended work:

- Create `docs/releases/v0.1.0.md`.
- Tag the exact release commit.
- Attach both the DMG and checksum file.
- Mark the GitHub Release as a pre-release because the app is self-signed and
  not notarized.
- Do not mark it as a fully trusted production macOS release.

Suggested commands:

```sh
git tag v0.1.0
git push origin v0.1.0
gh release create v0.1.0 \
  dist/GhostNotch-v0.1.0.dmg \
  dist/GhostNotch-v0.1.0.dmg.sha256 \
  --prerelease \
  --title "GhostNotch v0.1.0" \
  --notes-file docs/releases/v0.1.0.md
```

Definition of done:

- GitHub shows release `v0.1.0`.
- The release is marked pre-release.
- DMG and checksum are attached.
- README points users to the latest release.
- Release notes state that the DMG is self-signed and not notarized.

## Track 7: Future Trusted Release

Goal: Keep the next step clear without blocking v0.

When the project is ready for a lower-friction public release, move from
self-signed to Developer ID distribution:

1. Enroll in Apple Developer Program.
2. Create or let Xcode create a Developer ID Application certificate.
3. Configure Release signing.
4. Keep hardened runtime enabled.
5. Archive with Xcode.
6. Export or notarize using Developer ID distribution.
7. Staple the notarization ticket.
8. Verify with `spctl`.

Expected trusted-release `spctl` result:

```text
accepted
source=Notarized Developer ID
```

That future release can stop being labeled as a self-signed preview once this
path is complete.

## References

- Apple, Distribute outside the Mac App Store:
  https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html
- Apple, Test a Developer ID-signed app:
  https://help.apple.com/xcode/mac/current/en.lproj/dev1cc22a95c.html
- Apple, Program enrollment:
  https://developer.apple.com/help/account/membership/program-enrollment/
- GitHub, About releases:
  https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- GitHub, Managing releases:
  https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- create-dmg:
  https://github.com/create-dmg/create-dmg
- Sparkle, distribution notes:
  https://sparkle-project.org/documentation/

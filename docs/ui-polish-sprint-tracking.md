# GhostNotch v0.1.0 UI Polish Sprint Tracking

Status: Track 4 implementation complete; Track 3/4 performance evidence and live approval pending
Created: 2026-07-10
Depends on: [UI Polish Research Brief](ui-polish-research.md)

This tracker is the execution source of truth for the v0.1.0 styling and motion
sprint. Work in order unless the user explicitly approves the next implementation
slice while an evidence-only exit gate remains open. Open evidence gates must stay
visible and cannot be treated as complete.

## Status legend

- `[ ]` not started
- `[~]` in progress
- `[x]` complete with evidence linked or recorded
- `[!]` blocked; include the blocker directly under the item

## Locked decisions

- Target macOS 26 and raise the deployment target from 14.0 during this sprint.
- Use an Alcove-like balance: Dynamic Island fluidity, restrained macOS utility
  styling, opaque black notch shell.
- Cover all visible chrome, notch first. Do not modify the terminal canvas, font
  metrics, parser, PTY input/output behavior, or hook contracts. A read-only PTY
  descendant-process query is allowed only to identify a manually typed or
  launcher-started supported CLI and clear its identity after it exits.
- Keep the 220-by-38-point physical notch as hidden black space: place compact
  side marks directly against its left/right boundary instead of padding away
  from it. Keep visible screen-edge and bottom spacing equal.
- Use the approved 280-by-38-point collapsed shell and 420-by-104-point hover
  shell on the measured notch. In hover, keep 12 points at both screen edges and
  the bottom; the top of the glass control group begins at the hardware-notch
  boundary with no extra clearance.
- Use system-semantic typography, color, materials, and accessibility settings.
- Use clean-room Rose Three math; add no package and copy no external source.
- Keep static `Ready`, `Working`, and `Waiting` wording. Rose Three replaces the
  current animated trailing periods.
- Include this sprint in the v0.1.0 release gate.

## Track 0: Baseline and research handoff

Depends on: none

- [x] Record current code measurements, animation behavior, macOS/Xcode version,
  deployment target, and collapsed-state evidence in the research brief.
- [x] Record Apple guidance, product references, visual direction, motion
  storyboard, Rose Three source policy, and accessibility requirements.
- [x] Capture sanitized current-state images for hover, expanded, and Settings.
  Use suite `com.danielou.GhostNotch.UIPolishCapture` with two fixtures:
  `Project Docs`/`PD` and `Build Tools`/`BT`, rooted under
  `/tmp/ghostnotch-ui-polish/`; enable Codex and Claude. Render Settings with an
  injected `AgentPresetStore` backed by that suite. A temporary, uncommitted,
  Debug-only composition-root edit is allowed solely for this capture; save
  the pre-edit diff, remove the edit immediately afterward, and verify the
  source diff exactly matches the saved pre-edit diff before measuring
  performance. Then remove the suite and temporary folders.
  Evidence: [hover](images/ui-polish/baseline-hover.jpg),
  [expanded](images/ui-polish/baseline-expanded.jpg), and
  [Settings](images/ui-polish/baseline-settings.jpg) — 2026-07-11, Mac16,7,
  isolated `/tmp` fixtures.
- [x] Record current standard and Reduce Motion transition clips covering
  collapsed → hover → collapsed, collapsed → expanded → collapsed, and rapid
  reversal at every available display mode up to the highest rate, using the
  research filenames.
  Evidence: standard and Reduce Motion H.264 clips at 48, 50, 60, and 120 Hz
  under `docs/images/ui-polish/` — 2026-07-11, Mac16,7.
- [x] Create `docs/images/ui-polish/performance.md` and record three 60-second
  ready, working, and waiting CPU samples using the research measurement
  protocol before source changes begin.
  Evidence: [baseline performance](images/ui-polish/performance.md) —
  2026-07-11, Mac16,7, 120 Hz Time Profiler runs.

Exit gate:

- [x] Every surface has a sanitized baseline image and the motion recording is
  linked from the research brief.
- [x] No repo screenshot contains usernames, local paths, tokens, terminal
  history, or other personal data.
- [x] Save files using the names and formats in the research brief, verify the
  temporary capture edit left no source diff, and add an
  `Evidence:` entry under each completed capture task.
- [x] `performance.md` contains the current commit, hardware, active display
  refresh rate, raw samples, medians, and trace locations.

## Track 1: macOS 26 foundation

Depends on: Track 0

- [x] Run
  `rg -n 'MACOSX_DEPLOYMENT_TARGET|macOS 14|14\\.0' GhostNotch.xcodeproj README.md docs scripts`
  and record every non-archive compatibility consumer.
- [x] Set every GhostNotch app and test Debug/Release
  `MACOSX_DEPLOYMENT_TARGET` in `GhostNotch.xcodeproj/project.pbxproj` to 26.0.
  Do not clean up unrelated availability branches in this sprint.
- [x] Update README, release notes, build docs, and packaging assumptions from
  macOS 14 to macOS 26.
- [x] Inventory repeated chrome values. Keep values local unless at least two
  production surfaces must stay synchronized.
- [x] Define the minimal shared semantic values needed for notch controls:
  foreground roles, state colors, control size, local spacing, and corner
  treatment. Do not create a general token framework.
- [x] Add coverage for any extracted pure sizing or state-style logic.
  Evidence: all six deployment settings and the Zig default target 26.0;
  existing `IslandMetricsTests` covered the shared 40-by-32-point capsule
  geometry and then-current 112-point hover height (superseded by Track 4's
  approved 104-point geometry);
  `xcodebuild test` passed on 2026-07-11. Xcode's project-format
  `compatibilityVersion = "Xcode 14.0"` remains intentionally unchanged.

Exit gate:

- [x] Debug and Release builds target macOS 26 and tests pass.
- [x] Public requirements consistently say macOS 26 or newer.
- [x] The app has no new dependency or speculative styling layer.

## Track 2: Typography, spacing, and controls

Depends on: Track 1

- [x] Change hover status text to system-default `.caption`, Medium weight, and
  semantic secondary foreground. Keep it on one line.
- [x] Use 40-by-32-point quick-launch segments with a two-point outer capsule
  inset. Keep 8 points from status to controls, 12 points between folder and
  agent groups, and the then-current 24-point horizontal/12-point bottom
  padding. Track 4 supersedes the horizontal inset with 12 points on each side.
  Keep every native hover/press subcapsule centered at 36 by 28 points with a
  14% white tint so it remains visible inside the outer capsule while
  preserving the full click target.
- [x] Add `Folders` and `Agents` secondary `caption2` labels four points above
  two separate native outer glass capsules. Hide the folder label and capsule
  when there are no valid presets.
- [x] Put expanded restart/collapse actions in one native outer capsule and
  inset it from the screen top. Keep Settings on native grouped-Form controls.
- [x] Add clear hover, pressed, selected, disabled, and keyboard-focus states
  without changing actions or selection behavior. Use exact-size native inner
  glass only for hover/press. Put the selected folder's 43-by-35-point system
  blue backing, mixed 18% toward white, beneath the persistent outer glass so
  native refraction reaches only sibling folder segments. Add a solid
  36-by-28-point capsule in the same blue above the outer glass and below the
  folder icon. When Reduce Transparency is enabled, replace only the backing
  with a 43-by-35-point native tinted glass segment. Add no imitation glass
  surface or outline.
- [x] Keep the opaque black shell and apply semantic label/symbol colors.
- [x] Let native Liquid Glass respond to Reduce Transparency and Increase
  Contrast. Use semantic foregrounds and native focus/hover/press treatments;
  use `NSColor.separatorColor` only for the outer black shell rim.
- [x] Preserve the existing directory preset accessibility label and help
  formats (`Use <name> folder` and `<name> - <path>`), preserve each launcher's
  existing label/help text, and preserve `Restart terminal` and `Collapse
  terminal` for expanded actions. Verify each string with VoiceOver.
  Evidence: [standard hover](images/ui-polish/track2-hover-standard.jpg),
  [expanded actions](images/ui-polish/track2-expanded-standard.jpg),
  [Reduce Transparency](images/ui-polish/track2-hover-reduce-transparency.jpg),
  and [Increase Contrast](images/ui-polish/track2-hover-increase-contrast.jpg)
  — refreshed 2026-07-11, Mac16,7. The hover captures show the second folder
  selected and the first hovered; the expanded capture shows the contained
  restart hover. Accessibility inspection exposed every preserved label/help
  string.

Exit gate:

- [x] No controls clip with zero through three folder presets and one through
  two launchers.
- [x] Physical-notch clearance remains intact. The hover height changed from 90
  to 112 points to fit the caption row and native outer-capsule inset; collapsed
  and expanded dimensions remain unchanged. This is historical Track 2
  evidence; Track 4 intentionally removes the eight-point hidden-notch
  clearance and sets the final hover height to 104 points.
- [x] Pointer and VoiceOver labels/help work. Hover temporarily activates
  GhostNotch for focused native glass and restores the previous app on exit;
  expansion retains focus. Expanded terminal Tab input and native Settings
  keyboard behavior remain unchanged.

## Track 3: Coordinated notch motion

Depends on: Track 2

- [x] Make transition intent explicit for each state pair instead of selecting
  duration only from the destination state.
- [x] Coordinate panel frame, notch shape/rim, old-content exit, and new-content
  entrance using the storyboard in the research brief.
- [x] Start with `NSAnimationContext` plus state-specific timing and SwiftUI
  system springs. Measure it before adding custom frame-driving code.
  Evidence: the 2026-07-12 pass compiled and passed tests, but live review on
  2026-07-13 rejected its linear-feeling window resize and transient top gap.
- [x] Use a 0.22-second system spring for collapsed→hover, 0.18 seconds
  hover→collapsed, a 0.34-second system spring to expanded, and a 0.22-second
  ease-out close. Both opening springs use a 0.78 damping ratio and
  approximately 2% overshoot; content glides without bouncing.
- [x] Fade outgoing content in the first 35%; start hover controls and expanded
  header content at 25%, and terminal content at 35%. Hover controls use pure
  opacity with no vertical travel. On close, return compact content during the
  final 25% and finish it at shell settlement.
- [x] Implement immediate hover entry and a cancelable 0.04-second exit grace.
  Re-entry must cancel collapse without a visible jump.
- [x] Include the exact top screen edge in the shared hover entry/exit hit test;
  AppKit's default rectangle containment excludes that edge.
- [x] Make transitions interruptible: retarget from the visible state, ignore
  stale completion callbacks, and keep the last requested state.
- [x] Preserve `finishExpandPanelAnimation()` as the single point that marks the
  terminal ready and requests repaint/focus.
- [x] Replace the rejected window animator with one panel-linked
  `CADisplayLink`, sampling native `Spring.value`/`UnitCurve` progress. Remove
  the old production path and invalidate the link on retarget, completion, and
  teardown.
- [x] Keep the panel as the only owner of animated window size. Configure the
  `NSHostingView` with no content-derived sizing constraints or safe-area
  regions, and do not wrap the root state change in a second SwiftUI animation.
  Evidence: after the original path triggered AppKit's Update Constraints loop,
  live hover, expand, close, and reopen completed on one process with no new
  crash report on 2026-07-13.
- [x] Keep every intermediate frame top-centered and attached, including the
  spring overshoot, and add a one-physical-pixel shell-colored top seam guard.
- [x] Add the exact Reduce Motion behavior: resize directly to the target frame
  and cross-fade layouts over 0.08 seconds with ease-out only when both old and
  new layouts exist. Use no spring, scale, or overshoot.
  Evidence: `IslandTransitionPlanTests` cover every state-pair duration and
  curve, both 2% spring peaks, monotonic close, top attachment through
  overshoot, Reduce Motion, close-to-hover bounds, and stale-generation
  rejection; full `xcodebuild test` passed on 2026-07-13.
- [x] Remove the extra main-actor scheduling turn from collapsed↔hover while
  retaining layout staging for transitions involving expanded content.
- [x] Keep terminal processing active while compact, but publish render
  snapshots only while expanded content is mounted. Publish output lifecycle
  state only when its value changes and refresh the latest snapshot before
  expanded content appears.
- [x] Resolve valid directory presets and enabled launchers once per hover
  render pass, without persistent caching or changes to the Track 4 status
  indicator and trailing-period behavior.
- [x] Remove the collapsed Ghost mark immediately on hover entry instead of
  fading its fill, outline, and shadow while the panel spring is resizing.
  Keep the status-dot exit fade and the Ghost mark's close-state fade-in.
  Evidence: focused transition/publication tests, full `xcodebuild test`,
  `xcodebuild analyze`, and a clean Release build passed on 2026-07-14. A live
  Release smoke check covered launch, expand, collapse, terminal focus, and
  hidden terminal output without a crash. Direct pointer-hover pacing remains
  part of the performance and user-approval gates below.

Exit gate:

- [ ] Every transition settles within the research tuning bounds with no
  repeated oscillation.
- [ ] Rapid hover-edge movement, click-during-hover, hotkey reversal, and
  collapse-during-expand produce no flash, stale focus, or stuck state.
- [ ] In each of three runs of the research measurement protocol, average at
  least 95% of active display refresh, contain no 100 ms hitch, and finish in
  the requested state with correct focus. Do not average FPS across runs. After
  a failed first set, permit one evidence-led source revision limited to state
  invalidation and in-bounds timing, then one complete three-run retest. If it
  fails, remove optional content translation but retain the top-anchored display
  link, then rerun the complete gate. A second failure blocks Track 3.
- [ ] The user approves Standard and Reduce Motion in the live build. Retain one
  sanitized technical recording of each mode after approval.

## Track 4: Rose Three status and compact identity

Depends on: Track 3

- [x] Implement one clean-room Rose Three SwiftUI view from
  `r(θ) = a cos(3θ)` using native drawing and timeline APIs.
- [x] Use a 22-point footprint, 1.25-point ready stroke, and for active states a
  0.6-point guide at 12% opacity plus 18 particles, 1.5-point maximum particle
  diameter, 0.34-cycle trail span, and 1.8-second loop.
- [x] Render ready as a static system-green curve.
- [x] Render working as an animated white/primary curve and waiting as the same
  animation in system blue.
- [x] Render all states statically when Reduce Motion is enabled.
- [x] Ensure ready and reduced-motion states do not create a continuous
  timeline or measurable idle rendering loop.
- [x] Replace both collapsed and hover dots with the same component while
  preserving hover text and activity-state contracts.
- [x] Add pure tests for state-to-color/motion mapping, labels, rose bounds, and
  trail constants.
- [x] Use static hover labels `Ready`, `Working`, and `Waiting`; remove the
  animated trailing-period timeline.
- [x] Replace the collapsed Ghost mark with the active Codex or Claude asset in
  monochrome primary color for the CLI's full lifetime, including its ready
  state. Clear it when that CLI process exits; keep the left wing blank when no
  supported agent is running. Preserve the structured hook/state-file format.
- [x] Support launcher-started and manually typed Codex/Claude sessions by
  deriving identity from a recursive read-only descendant-process check before
  the first hook event. Keep hooks as the working/waiting status source.
  Cross-fade agent identity over 0.12 seconds, or update immediately with Reduce
  Motion.
- [x] Place both 22-point compact marks against the inner physical-notch
  boundary. The 30-point wings therefore derive equal 8-point top, outer, and
  bottom spacing without adding padding next to hidden hardware.
- [x] Remove the eight-point hover hardware-notch clearance, set hover to
  420-by-104 points on the measured notch, and use 12-point left, right, and
  bottom outer spacing.
  Evidence: `AgentStatusIndicatorStyleTests`, `IslandMetricsTests`, and
  `TerminalSessionTests` passed in the full suite on 2026-07-14; the tests cover
  geometry, motion/color/label mapping, Reduce Motion, and process-exit cleanup.
  A live Release harness on Mac16,7 verified blank Ready, Codex Ready/Working/
  Waiting, Claude Ready, real Codex process-exit cleanup, and the unchanged
  expanded terminal. The temporary startup seam and shell wrappers were removed,
  `AppDelegate.swift` returned to a clean diff, and the exact final source was
  rebuilt successfully. Pure pointer-hover motion, accessibility variants,
  formal CPU sampling, and user approval remain in the gates below.

Exit gate:

- [ ] Ready, working, and waiting plus Codex/Claude identity remain recognizable
  in collapsed and hover states at the approved 280-by-38 and 420-by-104 shell
  dimensions.
- [x] No external loader source, package, or copied implementation is present.
- [ ] Idle CPU returns to baseline after agent activity stops.
- [ ] Three 60-second samples meet the research thresholds against the matching
  Track 0 state median: final ready versus Track 0 ready adds at most 0.2 CPU
  percentage points; final working versus Track 0 working and final waiting
  versus Track 0 waiting each add at most 2.0 points.

## Track 5: Expanded chrome and Settings

Depends on: Tracks 2–4

- [ ] Give expanded restart/collapse buttons the same semantic symbol,
  hover/press, focus, contrast, and material rules as notch controls.
- [ ] Coordinate header appearance with expanded-shell settlement without
  changing the readiness event: `finishExpandPanelAnimation()` runs once after
  the panel frame reaches its target, then marks the surface ready and requests
  repaint/focus.
- [ ] Keep the native grouped Settings `Form`; improve hierarchy and row
  alignment using native labels, controls, spacing, and materials.
- [ ] Preserve folder picking, validation, reordering, removal, agent toggles,
  window width, and persistence behavior unless a sanitized capture documents
  a concrete layout failure.
- [ ] Add no decorative Settings animation.

Exit gate:

- [ ] Expanded actions and Settings look related to the notch controls without
  turning the terminal canvas into a glass surface.
- [ ] Existing Settings persistence tests pass and manual folder flows remain
  unchanged.

## Track 6: Acceptance and v0.1.0 release gate

Depends on: Tracks 1–5

Automated checks:

Track 4's interim 2026-07-14 verification passed `git diff --check`, both hook
self-tests, the full macOS test suite, static analysis, and the Release build.
The final boxes remain open because Track 6 depends on Track 5 and must rerun
against the eventual release source.

- [ ] `git diff --check`
- [ ] `python3 scripts/install-agent-hooks.py self-test`
- [ ] `python3 GhostNotch/Resources/ShellIntegration/ghostnotch-agent-hook --self-test`
- [ ] `xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'`
- [ ] `xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Release build`

Visual and interaction matrix:

- [ ] Collapsed, hover, expanded, and Settings before/after captures.
- [ ] Ready, working, and waiting in collapsed and hover states.
- [ ] Zero through three valid presets; invalid preset hidden; one through two
  launchers.
- [ ] Pointer entry/exit grace, rapid re-entry, selected preset, launch click,
  background click, `Option+Space`, outside click, and Escape behavior.
- [ ] Reduce Motion, Reduce Transparency, and Increase Contrast.
- [ ] Built-in notched display plus non-notch/fallback smoke check.
- [ ] Terminal focus, repaint, resize, session persistence, restart, launcher,
  and manual renderer checks from [Testing](testing.md).

Performance evidence:

- [ ] Each of three Instruments runs averages at least 95% of the active display
  refresh and contains no 100 ms hitch; do not average FPS across runs. If 120
  Hz hardware is unavailable, record the
  highest available rate and mark 120 Hz unavailable rather than failing.
- [ ] No sustained loader work in ready or Reduce Motion states.
- [ ] Working/waiting loader CPU use is recorded and accepted in the tracker.
- [ ] Store screenshots, the accepted standard and Reduce Motion H.264
  recordings, the two accessibility captures, and `performance.md`. Delete
  rejected recordings and raw traces after their measurements are transcribed.
  Add dated `Evidence:` links with hardware and accessibility mode.

Release closeout:

- [ ] Update the research brief with final constants, screenshots, recordings,
  and any accepted deviations.
- [ ] Update v0.1.0 release notes with macOS 26 requirement and polished UI
  summary.
- [ ] Mark the UI polish release gate complete in
  [v0 DMG Release Tracking](v0-dmg-release-tracking.md).
- [ ] Re-run packaging and manual Gatekeeper acceptance from the release
  tracker before tagging.

Final stop condition:

The sprint is complete only when every exit gate is checked, Blocker/Major
visual or interaction regressions are resolved, the measured motion and idle
costs are recorded, and v0.1.0 documentation matches the shipped behavior.

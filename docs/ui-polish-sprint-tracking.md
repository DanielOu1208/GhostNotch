# GhostNotch v0.1.0 UI Polish Sprint Tracking

Status: ready for Track 0; source implementation blocked by the Track 0 exit gate  
Created: 2026-07-10  
Depends on: [UI Polish Research Brief](ui-polish-research.md)

This tracker is the execution source of truth for the v0.1.0 styling and motion
sprint. Work in order. Do not begin a track until its dependencies and exit gate
are complete.

## Status legend

- `[ ]` not started
- `[~]` in progress
- `[x]` complete with evidence linked or recorded
- `[!]` blocked; include the blocker directly under the item

## Locked decisions

- Target macOS 26 and raise the deployment target from 14.0 during this sprint.
- Use an Alcove-like balance: Dynamic Island fluidity, restrained macOS utility
  styling, opaque black notch shell.
- Cover all visible chrome, notch first. Do not modify the terminal canvas,
  font metrics, parser, PTY, or hook contracts.
- Preserve current shell dimensions unless captured evidence proves a problem.
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
- [ ] Capture sanitized current-state images for hover, expanded, and Settings.
  Use suite `com.danielou.GhostNotch.UIPolishCapture` with two fixtures:
  `Project Docs`/`PD` and `Build Tools`/`BT`, rooted under
  `/tmp/ghostnotch-ui-polish/`; enable Codex and Claude. Render Settings with an
  injected `AgentPresetStore` backed by that suite. A temporary, uncommitted,
  Debug-only composition-root edit is allowed solely for this capture; save
  the pre-edit diff, remove the edit immediately afterward, and verify the
  source diff exactly matches the saved pre-edit diff before measuring
  performance. Then remove the suite and temporary folders.
- [ ] Record current standard and Reduce Motion transition clips covering
  collapsed → hover → collapsed, collapsed → expanded → collapsed, and rapid
  reversal at every available display mode up to the highest rate, using the
  research filenames.
- [ ] Create `docs/images/ui-polish/performance.md` and record three 60-second
  ready, working, and waiting CPU samples using the research measurement
  protocol before source changes begin.

Exit gate:

- [ ] Every surface has a sanitized baseline image and the motion recording is
  linked from the research brief.
- [ ] No repo screenshot contains usernames, local paths, tokens, terminal
  history, or other personal data.
- [ ] Save files using the names and formats in the research brief, verify the
  temporary capture edit left no source diff, and add an
  `Evidence:` entry under each completed capture task.
- [ ] `performance.md` contains the current commit, hardware, active display
  refresh rate, raw samples, medians, and trace locations.

## Track 1: macOS 26 foundation

Depends on: Track 0

- [ ] Run
  `rg -n 'MACOSX_DEPLOYMENT_TARGET|macOS 14|14\\.0' GhostNotch.xcodeproj README.md docs scripts`
  and record every non-archive compatibility consumer.
- [ ] Set every GhostNotch app and test Debug/Release
  `MACOSX_DEPLOYMENT_TARGET` in `GhostNotch.xcodeproj/project.pbxproj` to 26.0.
  Do not clean up unrelated availability branches in this sprint.
- [ ] Update README, release notes, build docs, and packaging assumptions from
  macOS 14 to macOS 26.
- [ ] Inventory repeated chrome values. Keep values local unless at least two
  production surfaces must stay synchronized.
- [ ] Define the minimal shared semantic values needed for notch controls:
  foreground roles, state colors, control size, local spacing, and corner
  treatment. Do not create a general token framework.
- [ ] Add coverage for any extracted pure sizing or state-style logic.

Exit gate:

- [ ] Debug and Release builds target macOS 26 and tests pass.
- [ ] Public requirements consistently say macOS 26 or newer.
- [ ] The app has no new dependency or speculative styling layer.

## Track 2: Typography, spacing, and controls

Depends on: Track 1

- [ ] Change hover status text to system-default `.caption`, Medium weight, and
  semantic secondary foreground. Keep it on one line.
- [ ] Preserve 32-point quick-launch targets and normalize internal gaps using
  the research map: 4 points symbol-to-label, 6 points within the glass
  container, 8 points from status to the first controls, and 12 points between
  preset and launcher groups. Preserve 24-point horizontal and 12-point bottom
  hover padding.
- [ ] Put preset and launcher buttons in one
  `GlassEffectContainer(spacing: 6)`. Use standard glass for unselected buttons
  and prominent glass for the selected preset.
- [ ] Use standard glass for expanded restart/collapse buttons. Keep Settings
  on native grouped-Form controls without custom glass.
- [ ] Add clear hover, pressed, selected, disabled, and keyboard-focus states
  without changing actions or selection behavior. Use native glass hover and
  press feedback, prominent glass only for selection, the system disabled
  treatment, and the system keyboard focus ring; do not layer custom versions
  of those states.
- [ ] Keep the opaque black shell and apply semantic label/symbol colors.
- [ ] With Reduce Transparency, use opaque `NSColor.controlBackgroundColor`
  with a one-point `NSColor.separatorColor` outline. With Increase Contrast,
  use a two-point semantic separator outline and keep text at 4.5:1 and control
  boundaries at 3:1 in Accessibility Inspector.
- [ ] Preserve the existing directory preset accessibility label and help
  formats (`Use <name> folder` and `<name> - <path>`), preserve each launcher's
  existing label/help text, and preserve `Restart terminal` and `Collapse
  terminal` for expanded actions. Verify each string with VoiceOver.

Exit gate:

- [ ] No control clips with zero through three folder presets and one through
  three launchers.
- [ ] Physical-notch clearance and current shell dimensions remain unchanged,
  or the tracker includes the screenshot that justified a dimension change.
- [ ] Pointer, keyboard, VoiceOver labels, help text, and focus behavior work.

## Track 3: Coordinated notch motion

Depends on: Track 2

- [ ] Make transition intent explicit for each state pair instead of selecting
  duration only from the destination state.
- [ ] Coordinate panel frame, notch shape/rim, old-content exit, and new-content
  entrance using the storyboard in the research brief.
- [ ] Start with `NSAnimationContext` plus state-specific timing and SwiftUI
  system springs. Measure it before adding custom frame-driving code.
- [ ] Start with 0.22 seconds collapsed→hover, 0.18 seconds hover→collapsed,
  0.28 seconds to expanded, and 0.24 seconds expanded→collapsed. Use matching
  `snappy` content springs with `extraBounce = 0.02`.
- [ ] Fade outgoing content in the first 35%; start incoming content at 25% and
  finish it at shell settlement.
- [ ] Implement immediate hover entry and a cancelable 0.12-second exit grace.
  Re-entry must cancel collapse without a visible jump.
- [ ] Make transitions interruptible: retarget from the visible state, ignore
  stale completion callbacks, and keep the last requested state.
- [ ] Preserve `finishExpandPanelAnimation()` as the single point that marks the
  terminal ready and requests repaint/focus.
- [ ] If the platform animator fails frame-pacing or interruption gates, replace
  it with one screen-linked spring driver and remove the rejected production
  path.
- [ ] Add the exact Reduce Motion behavior: resize directly to the target frame
  and cross-fade layouts over 0.08 seconds with ease-out only when both old and
  new layouts exist. Use no spring, scale, or overshoot.

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
  fails, use the display-linked driver.

## Track 4: Rose Three status indicator

Depends on: Track 3

- [ ] Implement one clean-room Rose Three SwiftUI view from
  `r(θ) = a cos(3θ)` using native drawing and timeline APIs.
- [ ] Use a 14-point footprint, 1.25-point ready stroke, and for active states a
  0.6-point guide at 12% opacity plus 18 particles, 1.5-point maximum particle
  diameter, 0.34-cycle trail span, and 1.8-second loop.
- [ ] Render ready as a static system-green curve.
- [ ] Render working as an animated white/primary curve and waiting as the same
  animation in system blue.
- [ ] Render all states statically when Reduce Motion is enabled.
- [ ] Ensure ready and reduced-motion states do not create a continuous
  timeline or measurable idle rendering loop.
- [ ] Replace both collapsed and hover dots with the same component while
  preserving hover text and activity-state contracts.
- [ ] Add pure tests for state-to-color/motion mapping and accessibility labels.
- [ ] Use static hover labels `Ready`, `Working`, and `Waiting`; remove the
  animated trailing-period timeline.

Exit gate:

- [ ] Ready, working, and waiting remain recognizable in collapsed and hover
  states without changing shell dimensions.
- [ ] No external loader source, package, or copied implementation is present.
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

- [ ] `git diff --check`
- [ ] `python3 scripts/install-agent-hooks.py self-test`
- [ ] `python3 GhostNotch/Resources/ShellIntegration/ghostnotch-agent-hook --self-test`
- [ ] `xcodebuild test -project GhostNotch.xcodeproj -scheme GhostNotch -destination 'platform=macOS'`
- [ ] `xcodebuild -project GhostNotch.xcodeproj -scheme GhostNotch -configuration Release build`

Visual and interaction matrix:

- [ ] Collapsed, hover, expanded, and Settings before/after captures.
- [ ] Ready, working, and waiting in collapsed and hover states.
- [ ] Zero through three valid presets; invalid preset hidden; one through three
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
- [ ] Store screenshots, the standard and Reduce Motion H.264 recordings under
  20 MB each for every tested refresh mode, the two accessibility captures,
  and `performance.md` using the research brief's names. Add dated `Evidence:`
  links with hardware and accessibility mode to completed tasks.

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

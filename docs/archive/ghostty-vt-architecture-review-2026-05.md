# Ghostty VT Deep Code Review

> Historical architecture review. Current architecture guidance lives in [`../architecture.md`](../architecture.md).

Date: 2026-05-23

This review evaluates GhostNotch's current Ghostty-backed terminal implementation against Ghostty/libghostty and cmux. It focuses on architectural correctness, maintainability, redundant code, and concrete refactor opportunities.

External references checked:

- Ghostty repository: <https://github.com/ghostty-org/ghostty>
- Ghostty embedding header: <https://github.com/ghostty-org/ghostty/blob/main/include/ghostty.h>
- Ghostty surface implementation: <https://github.com/ghostty-org/ghostty/blob/main/src/Surface.zig>
- Ghostty VT render example: <https://github.com/ghostty-org/ghostty/blob/main/example/c-vt-render/src/main.c>
- cmux repository: <https://github.com/manaflow-ai/cmux>
- cmux terminal surface source: <https://github.com/manaflow-ai/cmux/blob/main/Sources/GhosttyTerminalView.swift>
- cmux configuration docs: <https://cmux.com/docs/configuration>

## Executive summary

GhostNotch's current `ghosttylib` implementation is a solid VT-state MVP, but it is not architecturally equivalent to Ghostty/libghostty or cmux. The implementation uses a vendored `libghostty-vt` artifact for terminal state, render snapshots, key encoding, paste encoding, focus encoding, and terminal write-back behavior. GhostNotch still owns the AppKit/CoreText renderer, font handling, selection, mouse behavior, PTY lifecycle, and panel UI.

That is acceptable if the near-term goal is "VT parser plus custom notch renderer." If the goal is to wrap Ghostty like cmux, the current boundary is too low-level and will keep accumulating duplicated terminal application work.

The largest architectural risks are:

- The code can imply "Ghostty-like terminal engine" while only wrapping `libghostty-vt`, not full `libghostty`.
- Rendering, font fallback, glyph sprites, cursor drawing, selection, mouse, and input policy are being recreated in Swift/AppKit.
- `IslandPanelController` mixes UI/window state with terminal session, renderer, focus, resize, and restart policy.
- The snapshot/render path does full-grid work after every output chunk rather than using Ghostty dirty-state concepts.

## High-priority issues

### 1. The `ghosttylib` boundary is really `libghostty-vt`, not full `libghostty`

- File/function/class name: `GhostNotch/Terminal/GhosttyVTBridge.c`, `GhostNotch/Terminal/GhosttyTerminalCore.swift`, `GhostNotch/UI/TerminalGridView.swift`
- What is wrong: The app creates a Ghostty VT terminal, updates a render state, extracts visible cells, then renders those cells itself. That matches Ghostty's `libghostty-vt` example pattern, not cmux's full `ghostty_app_t` / `ghostty_surface_t` embedding pattern.
- Why it matters: The abstraction name and architecture can invite false parity claims. The app is wrapping Ghostty's VT/render-state boundary, not Ghostty's renderer, font system, config system, or terminal application surface.
- Suggested fix: Rename or document this layer as a VT boundary, for example `GhosttyVTTerminalCore` or `GhosttyVTBackend`. Keep docs explicit that this is not full `libghostty` until the app embeds `ghostty_surface_t`.
- Severity: High

### 2. Rendering duplicates Ghostty renderer, font, and sprite responsibilities

- File/function/class name: `TerminalGridView`, `TerminalGridTypography`, `TerminalCellGlyphRenderer`, `TerminalTextDecorationRenderer`
- What is wrong: GhostNotch hand-renders every cell, chooses fonts, draws block/box/powerline fallback glyphs, draws decorations, draws cursor styles, and owns selection highlighting. Ghostty has dedicated renderer, font, shaper, and sprite subsystems for this work.
- Why it matters: Font fallback, ligatures, private-use glyphs, emoji, sprite glyphs, cursor behavior, and performance will drift from Ghostty. The manual renderer acceptance findings already note private-use glyph and font-selection weakness.
- Suggested fix: Short term, treat this as a custom MVP renderer and avoid expanding it beyond targeted fixes. Medium term, isolate it behind a dedicated `TerminalRenderer` boundary. Long term, evaluate replacing it with full Ghostty surface rendering.
- Severity: High

### 3. Input and mouse handling are too incomplete for Ghostty parity

- File/function/class name: `TerminalKeyEvent+AppKit.swift`, `GhosttyVTBridge.h`, `GhosttyVTBridge.c`, `TerminalGridView.scrollWheel(with:)`
- What is wrong: The Swift key model mirrors only a small subset of Ghostty keys and omits many physical keys, modifier transitions, key-up semantics, keypad keys, IME edge cases, and configured keybinding behavior. Mouse reporting is not implemented; alternate-screen wheel events currently fall through to AppKit.
- Why it matters: TUIs, IME/dead-key paths, keypad input, mouse tracking, scroll wheels, and Ghostty-style keybindings will behave differently from Ghostty and cmux. cmux routes key, mouse, scroll, focus, selection, and paste through Ghostty surface APIs.
- Suggested fix: For the VT-only path, expose Ghostty mouse encoder support and broaden key mapping from physical AppKit event data. For a full `libghostty` path, delegate directly to `ghostty_surface_key`, `ghostty_surface_mouse_*`, and `ghostty_surface_mouse_scroll`.
- Severity: High

### 4. `IslandPanelController` mixes panel UI with terminal engine/session policy

- File/function/class name: `GhostNotch/Window/IslandPanelController.swift`
- What is wrong: The controller owns panel state, hover monitors, outside-click behavior, PTY lifecycle, renderer wiring, focus/blur semantics, resize normalization, restart behavior, and snapshot publication.
- Why it matters: Terminal behavior changes require editing window/panel code. UI transitions can accidentally affect PTY or render state. This also makes future pane/session features harder to add cleanly.
- Suggested fix: Introduce a `TerminalSurfaceCoordinator` owned by the controller. It should own `TerminalSession`, `TerminalRenderingEngine`, snapshot publication, resize/focus/restart policy, and output batching. Leave `IslandPanelController` focused on window state and panel transitions.
- Severity: High

### 5. Rendering does full-grid work on every output chunk

- File/function/class name: `GhosttyTerminalCore.refreshSnapshot`, `TerminalGridView.draw(_:)`
- What is wrong: Each PTY output refresh allocates cell and grapheme arrays, maps every visible cell into Swift structs, publishes a full `TerminalRenderSnapshot`, and then the AppKit view loops over all rows and columns.
- Why it matters: Bulk output, `top`, `vim`, `less`, scrollback movement, and high-frequency PTY output can saturate the main actor and AppKit drawing. Ghostty's VT render example exposes dirty-state and dirty-row concepts specifically to avoid unnecessary renderer work.
- Suggested fix: Expose render dirty state and dirty row metadata from `GhosttyVTBridge`, coalesce PTY output before publishing snapshots, and invalidate only affected row rects where feasible.
- Severity: Medium

### 6. Terminal output is stored twice

- File/function/class name: `TerminalSessionState.outputData`, `TerminalSession.process.onOutput`
- What is wrong: Raw output bytes are appended to `TerminalSessionState` while `GhosttyTerminalCore` also owns terminal state and scrollback. The raw output buffer is mainly used for startup messaging and tests.
- Why it matters: This duplicates memory and mixes lifecycle/status state with terminal data. As scrollback grows, the raw buffer becomes a second terminal data model.
- Suggested fix: Replace `outputData` with smaller state such as `hasReceivedOutput`, plus optional debug/test capture. Let Ghostty own terminal output state.
- Severity: Medium

### 7. PTY I/O lacks batching and backpressure

- File/function/class name: `PTYProcess.readAvailableOutput(generation:)`
- What is wrong: Each read schedules a `Task { @MainActor ... }` with no coalescing. `PTYProcess` is `@unchecked Sendable` with manual locks around process state.
- Why it matters: Large output can queue many main-actor tasks, increasing input latency and render churn.
- Suggested fix: Add a small output coalescer or an `AsyncStream<Data>` consumed by the terminal coordinator. Batch reads per run-loop tick or frame before calling the render engine.
- Severity: Medium

### 8. Presentation code creates a Ghostty terminal core for static messages

- File/function/class name: `TerminalChromePresentation.make`, `TerminalRenderSnapshot.message(_:)`
- What is wrong: Startup/error/stopped status messages create a `GhosttyTerminalCore` just to produce a static text snapshot.
- Why it matters: Presentation code now depends on terminal engine construction and the C bridge being healthy. It also adds unnecessary allocation and initialization.
- Suggested fix: Build status overlays outside the terminal snapshot, or cache static message snapshots. Prefer not constructing a terminal core from chrome presentation code.
- Severity: Medium

### 9. Restart uses hard-coded cell pixel dimensions

- File/function/class name: `IslandPanelController.restartTerminal()`
- What is wrong: Restart normalizes the grid with `8x16` cell pixels instead of the last measured resize from the actual view.
- Why it matters: It can drift from the CoreText-measured cell size and cause PTY dimension changes after restart.
- Suggested fix: Use `terminalEngine.lastAppliedGridResize` when available, falling back to snapshot dimensions only when no measurement exists.
- Severity: Medium

## Redundant or unnecessary code

- `TerminalInputMapping.data(forInsertedText:)` appears app-unused and is only test-covered as a legacy helper. Keyboard input now uses `TerminalKeyEvent`.
- `GhosttyTerminalCore.scrollToBottom()` and `GNVTTerminalScrollToBottom()` are implemented but not exposed through `TerminalRenderingEngine`.
- `TerminalColor.ansi(index:bright:)` is only used in tests. The real palette also lives in `GhosttyVTBridge.c`, so palette policy is duplicated.
- `TerminalKey`, `GNVTKey`, and the `GNVTGhosttyKeyFromKey` C switch create three layers of duplicated key identity before reaching Ghostty.
- `TerminalCellGlyphRenderer` is useful only while GhostNotch owns rendering. If the app moves to full `libghostty`, most hand-drawn block/box/powerline fallback rendering becomes unnecessary.

## Maintainability issues

- `GhosttyVTBridge.c` currently handles allocation, terminal creation, render-state creation, palette policy, device attributes, key mapping, snapshot extraction, scroll, paste, and focus. Split policy constants and mapping helpers away from the public bridge operations.
- `GhosttyTerminalCore.swift` contains the Swift wrapper, key model, modifier model, Ghostty key mapping, write callback, cell conversion, and color conversion. Move key types and snapshot conversion into separate files.
- `TerminalRenderSnapshot` mixes render data with text extraction and selection behavior. Selection will become harder once scrollback, semantic selection, hyperlinks, and alternate-screen behavior improve.
- `GhosttyTerminalEngine` sounds like a full Ghostty engine, but it is a VT snapshot adapter plus a session writer. Consider naming that makes the current responsibility explicit.
- Config is absent from the terminal boundary. cmux reads Ghostty config for terminal rendering and keeps app settings separate; GhostNotch currently hard-codes font, palette, scrollback, `TERM`, and option-as-alt policy.

## Architecture comparison with Ghostty/libghostty

Ghostty's source separates terminal concerns across surfaces, terminal I/O, renderer, font, config, input, and platform runtime modules. `Surface.zig` describes a terminal surface as the widget where the terminal is drawn and responds to keyboard and mouse events. The surface owns or coordinates terminal I/O, renderer, renderer thread, font structures, derived config, mouse state, keyboard state, and platform runtime surface. The renderer subsystem is explicit and backend-specific, with Metal on macOS.

Ghostty exposes two relevant boundaries:

- Full embedding API in `include/ghostty.h`, with app/config/surface types such as `ghostty_app_t`, `ghostty_config_t`, and `ghostty_surface_t`.
- VT/render-state API under `include/ghostty/vt.h`, where consumers create a terminal, feed VT bytes, update a render state, inspect dirty state, iterate rows/cells, and render themselves.

GhostNotch currently uses the second boundary. It is aligned with `libghostty-vt`, not with full `libghostty` embedding.

That means GhostNotch has a clean-ish terminal emulation boundary, because VT parsing and terminal state are delegated to Ghostty. But rendering, font handling, selection, input policy, mouse behavior, PTY lifecycle, and platform surface behavior remain GhostNotch-owned.

## Architecture comparison with cmux

cmux appears to build a terminal/multiplexer experience on top of Ghostty's fuller app/surface embedding API. It creates a process-wide Ghostty app, loads Ghostty config, creates terminal surfaces with `ghostty_surface_new`, attaches them to `NSView`, passes command/working-directory/environment, sets display ID, content scale, size, focus, and then delegates key, mouse, scroll, selection, paste, and rendering into Ghostty surface APIs.

cmux owns the multiplexer/workspace/browser/sidebar/notification layer around the Ghostty surface. It does not recreate a full AppKit terminal grid renderer from render-state cells in the way GhostNotch currently does.

This is the key difference:

- cmux uses Ghostty as the terminal surface and renderer, then builds multiplexer UX around it.
- GhostNotch uses Ghostty as a VT state machine and render-state provider, then builds its own terminal surface and renderer around that.

Both can be valid, but they should not be described as the same architecture.

## Recommended refactor plan

### 1. Quick cleanup

- Rename or document the implementation as a `libghostty-vt` boundary, not full `libghostty`.
- Remove or quarantine unused helpers such as `data(forInsertedText:)` and unexposed `scrollToBottom`.
- Replace hard-coded restart cell pixels with `lastAppliedGridResize` when available.
- Split key types and snapshot conversion out of `GhosttyTerminalCore.swift`.
- Add a short comment in `GhosttyVTBridge.c` explaining that palette, device attributes, and scrollback limit are GhostNotch policy choices.

### 2. Medium refactors

- Introduce `TerminalSurfaceCoordinator` between `IslandPanelController` and the terminal internals.
- Add PTY output coalescing before `GhosttyTerminalCore.processOutput`.
- Expose Ghostty render dirty state and dirty rows through `GhosttyVTBridge`.
- Implement R8 alternate-screen wheel behavior with a hybrid policy:
  - Primary screen: scroll Ghostty viewport.
  - Alternate screen without mouse tracking: translate wheel into navigation keys.
  - Mouse tracking enabled: encode mouse wheel events through Ghostty mouse helpers.
- Reduce `TerminalSessionState` to lifecycle/status state and stop retaining a second raw-output buffer outside test/debug hooks.

### 3. Larger architectural changes

- Run a spike against full `libghostty`/`ghostty_surface_t` on macOS, modeled closer to cmux.
- The spike should create a Ghostty app/config/surface, attach it to an `NSView`, set size/scale/display/focus, launch a shell, and verify rendering, input, scroll, paste, and focus.
- If the spike is viable, plan a migration that retires most custom grid rendering, font handling, key mapping, mouse handling, and selection code.
- If the spike is not viable, keep the VT renderer but formalize it as a custom compatibility renderer with explicit non-parity docs and focused acceptance tests.

## Concrete examples

### Move terminal ownership out of the panel controller

Current controller wiring:

```swift
terminalSession.addOutputObserver { [weak self] data in
    self?.terminalEngine.processOutput(data)
}
```

Better ownership:

```swift
@MainActor
final class TerminalSurfaceCoordinator {
    let session: TerminalSession
    let engine: TerminalRenderingEngine

    func startIfNeeded(size: TerminalGridResize) throws
    func handleOutputBatch(_ data: Data)
    func resize(_ resize: TerminalGridResize)
    func restartPreservingGrid() throws
}
```

Then `IslandPanelController` calls the coordinator and does not need to know how PTY output feeds the renderer.

### Preserve measured grid dimensions on restart

Current restart sizing:

```swift
let resize = TerminalGridResize.normalized(
    columns: terminalSnapshot.columns,
    rows: terminalSnapshot.rows,
    cellWidthPixels: 8,
    cellHeightPixels: 16
)
```

Safer:

```swift
let resize = terminalEngine.lastAppliedGridResize
    ?? TerminalGridResize.normalized(
        columns: terminalSnapshot.columns,
        rows: terminalSnapshot.rows,
        cellWidthPixels: 8,
        cellHeightPixels: 16
    )
```

### Coalesce output and publish dirty render frames

Current path:

```swift
processOutput(data)
refreshSnapshot()
publishSnapshot()
draw every cell
```

Better VT-only path:

```swift
processOutput(coalescedData)
let frame = bridge.snapshot(includeDirtyRows: true)
publish(frame)
view.setNeedsDisplay(frame.dirtyRects)
```

### Clarify the type names

Current names imply a broader Ghostty engine:

```swift
final class GhosttyTerminalEngine
final class GhosttyTerminalCore
```

More accurate names for the current architecture:

```swift
final class GhosttyVTRenderStateEngine
final class GhosttyVTTerminalCore
```

Those names make it harder to accidentally treat the code as full Ghostty renderer embedding.

## Verification notes

This review was source-level and architecture-level. The Xcode test suite was not run as part of creating the review.

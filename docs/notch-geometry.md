# MacBook Notch Geometry Research

This note captures the notch sizing reference and current UI geometry for
GhostNotch so layout remains tied to real MacBook notch measurements.

## Sources and Measurement Method

Apple does not publish physical notch width, height, or corner radius in MacBook tech specs. The reliable runtime source is AppKit:

- `NSScreen.safeAreaInsets.top` reports the top area obscured by the camera housing on notched Macs.
- `NSScreen.auxiliaryTopLeftArea` and `NSScreen.auxiliaryTopRightArea` report the usable top-left and top-right areas beside the notch.
- Notch width can be computed as:

```swift
notchWidth = screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width
notchHeight = screen.safeAreaInsets.top
```

References:

- [Apple Developer Documentation: `NSScreen.safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) says the safe area reflects portions of the screen covered by the camera housing.
- [Apple Developer Documentation: `NSScreen.auxiliaryTopLeftArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-4ow3p) and `auxiliaryTopRightArea` expose the unobscured top areas beside the notch.
- [NotchTerminal's `NSScreen+Notch` docs](https://www.mintlify.com/iDams/NotchTerminal/api/nsscreen-notch) use the same calculation above.
- Apple tech specs confirm native display resolutions for current notched Apple silicon MacBook families, but not notch geometry:
  - [MacBook Pro 14-inch M4 Pro/Max, 2024](https://support.apple.com/en-us/121553)
  - [MacBook Pro 16-inch, 2021](https://support.apple.com/en-us/111901)
  - [MacBook Air 13.6-inch M2, 2022](https://support.apple.com/kb/SP869)
  - [MacBook Air 15-inch M2, 2023](https://support.apple.com/en-us/111346)

## Local Measurement

Measured on this machine via AppKit:

```text
Screen: Built-in Retina Display
Logical frame: 2056 x 1329 pt
Backing scale: 2.0
safeAreaInsets.top: 38 pt
auxiliaryTopLeftArea: 918 x 38 pt
auxiliaryTopRightArea: 918 x 38 pt
Computed physical notch: 220 x 38 pt
Computed physical notch in backing pixels: 440 x 76 px
```

This is the most important number for the current prototype.

The previous collapsed GhostNotch width was `232 pt`, only `12 pt` wider than the measured physical notch. That creates a visible extension of only `6 pt` per side, which is too small to read as an active indicator.

## Apple Silicon MacBook Display Context

Known notched Apple silicon MacBooks include:

```text
MacBook Pro 14-inch: 3024 x 1964 native pixels, normally 1512 x 982 pt at 2x
MacBook Pro 16-inch: 3456 x 2234 native pixels, normally 1728 x 1117 pt at 2x
MacBook Air 13.6-inch: 2560 x 1664 native pixels, normally 1280 x 832 pt at 2x
MacBook Air 15.3-inch: 2880 x 1864 native pixels, normally 1440 x 932 pt at 2x
```

Do not hard-code these as notch sizes. Use AppKit at runtime when possible because display scaling and model differences affect logical coordinates.

## Current GhostNotch Geometry

For the current measured `220 x 38 pt` physical notch, the approved constants
are:

```text
physical notch reference: 220 x 38 pt
collapsed visual width: 280 pt
collapsed visual height: 38 pt
collapsed extension beyond notch: 30 pt per side
compact mark: 22 pt
compact visible top, outer, and bottom spacing: 8 pt

hover visual width: 420 pt
hover visual height: 104 pt
hover extension beyond notch: 100 pt per side
hover left, right, and bottom spacing: 12 pt
hover clearance below physical notch: 0 pt

expanded visual width: 822.8 pt
expanded visual height: 562 pt
```

The runtime formulas are:

```text
collapsedWidth = notchWidth + 60
collapsedHeight = max(notchHeight, 38)
hoverWidth = max(notchWidth + 200, 420)
hoverHeight = max(104, notchHeight + 14 + 4 + 32 + 4 + 12)
```

## Corner Curvature Guidance

AppKit exposes notch width and height, but not the physical notch corner radius. Public Apple tech specs do not publish the radius either.

For the visual shape, use top-flush geometry with only the bottom corners rounded. Avoid full pill curvature for collapsed and hover states because the real MacBook notch is a top-attached camera housing, not a floating capsule.

Current radii:

```text
collapsed bottom corner radius: 14 pt
hover bottom corner radius: 14 pt
expanded bottom corner radius: 18 pt
```

These radii are intentionally smaller than half the height. They keep the shape notch-like instead of pill-like while still feeling Apple-like and softened.

When tuning visually:

- If the extension looks like a capsule, reduce radius.
- If it looks like a blocky rectangle, increase radius by 2-4 pt.
- Keep the top edge perfectly flat and flush with the screen top.
- Put active indicators in the side extensions, not in the hardware notch center.
- Do not add content padding beside the physical notch: the black shell and black
  camera housing are visually continuous. Apply equal spacing only at visible
  screen edges and the bottom.

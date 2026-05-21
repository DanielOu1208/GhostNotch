import AppKit
import CoreText
struct TerminalGridTypography {
    let regularFont: NSFont
    let boldFont: NSFont
    let cellSize: NSSize
    let baselineOffset: CGFloat

    init(size: CGFloat) {
        regularFont = Self.makeFont(size: size, weight: .regular)
        boldFont = Self.makeFont(size: size, weight: .semibold, matching: regularFont)
        let regularCTFont = regularFont as CTFont
        let advance = CTFontGetAdvancesForGlyphs(regularCTFont, .horizontal, [Self.measurementGlyph(for: regularCTFont)], nil, 1)
        let width = ceil(advance)
        let ascent = ceil(CTFontGetAscent(regularCTFont))
        let descent = ceil(CTFontGetDescent(regularCTFont))
        let leading = ceil(CTFontGetLeading(regularCTFont))
        cellSize = NSSize(width: max(width, 7), height: max(ascent + descent + leading + 1, 14))
        baselineOffset = max(1, floor((cellSize.height - ascent - descent) / 2)) + ascent
    }

    func draw(_ text: String, style: TerminalCellStyle, foreground: NSColor, in rect: NSRect, viewHeight: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let baseFont = style.isBold ? boldFont : regularFont
        let drawFont = Self.font(for: text, baseFont: baseFont)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): drawFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground.cgColor,
            .ligature: 1,
        ]
        if style.isItalic {
            attributes[.obliqueness] = 0.18
        }

        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: viewHeight)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: rect.minX, y: viewHeight - rect.minY - baselineOffset)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    func supports(_ text: String) -> Bool {
        Self.supports(text, font: regularFont as CTFont)
    }

    private static func makeFont(size: CGFloat, weight: NSFont.Weight, matching baseFont: NSFont? = nil) -> NSFont {
        if let baseFont,
           let weightedFont = NSFont(
            descriptor: baseFont.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
            ]),
            size: size
           ) {
            return weightedFont
        }

        for name in preferredInstalledFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func font(for text: String, baseFont: NSFont) -> CTFont {
        let baseCTFont = baseFont as CTFont
        guard !text.isEmpty else {
            return baseCTFont
        }

        guard !supports(text, font: baseCTFont) else {
            return baseCTFont
        }

        for name in preferredInstalledFontNames {
            guard let fallbackFont = NSFont(name: name, size: baseFont.pointSize) else {
                continue
            }
            let fallbackCTFont = fallbackFont as CTFont
            if supports(text, font: fallbackCTFont) {
                return fallbackCTFont
            }
        }

        return CTFontCreateForString(baseCTFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
    }

    private static func supports(_ text: String, font: CTFont) -> Bool {
        guard !text.isEmpty else {
            return true
        }

        let codeUnits = Array(text.utf16).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: codeUnits.count)
        return codeUnits.withUnsafeBufferPointer { codeUnitBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(font, codeUnitBuffer.baseAddress!, glyphBuffer.baseAddress!, codeUnitBuffer.count)
            }
        }
    }

    private static func measurementGlyph(for font: CTFont) -> CGGlyph {
        var character: UniChar = 87
        var glyph = CGGlyph()
        _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        return glyph
    }

    private static let preferredInstalledFontNames = [
        "MesloLGS NF",
        "MesloLGS NF Regular",
        "JetBrainsMono Nerd Font",
        "JetBrains Mono NL",
        "Hack Nerd Font",
        "FiraCode Nerd Font",
        "Menlo",
    ]
}

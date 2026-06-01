import AppKit
import CoreText
final class TerminalGridTypography {
    private static let maximumCacheEntries = 512

    let regularFont: NSFont
    let boldFont: NSFont
    let cellSize: NSSize
    let baselineOffset: CGFloat
    private let fallbackFonts: [NSFont]
    private var supportCache: [String: Bool] = [:]
    private var fontCache: [String: CTFont] = [:]

    init(size: CGFloat) {
        regularFont = Self.makeFont(size: size, weight: .regular)
        boldFont = Self.makeFont(size: size, weight: .semibold, matching: regularFont)
        fallbackFonts = Self.makeFallbackFonts(size: size)
        let regularCTFont = regularFont as CTFont
        let advance = CTFontGetAdvancesForGlyphs(regularCTFont, .horizontal, [Self.measurementGlyph(for: regularCTFont)], nil, 1)
        let width = ceil(advance)
        let ascent = ceil(CTFontGetAscent(regularCTFont))
        let descent = ceil(CTFontGetDescent(regularCTFont))
        let leading = ceil(CTFontGetLeading(regularCTFont))
        cellSize = NSSize(width: max(width, 7), height: max(ascent + descent + leading + 1, 14))
        baselineOffset = max(1, floor((cellSize.height - ascent - descent) / 2)) + ascent
        Self.logFontDiagnostics(font: regularFont)
    }

    func draw(_ text: String, style: TerminalCellStyle, foreground: NSColor, in rect: NSRect, viewHeight: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let baseFont = style.isBold ? boldFont : regularFont
        let drawFont = font(for: text, baseFont: baseFont)
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
        supports(text, font: regularFont as CTFont)
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

        for name in preferredInstalledFontNames() {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private func font(for text: String, baseFont: NSFont) -> CTFont {
        let baseCTFont = baseFont as CTFont
        guard !text.isEmpty else {
            return baseCTFont
        }

        let cacheKey = "\(baseFont.fontName)|\(text)"
        if let cachedFont = fontCache[cacheKey] {
            return cachedFont
        }

        guard !supports(text, font: baseCTFont) else {
            cacheFont(baseCTFont, for: cacheKey)
            return baseCTFont
        }

        for fallbackFont in fallbackFonts where fallbackFont.pointSize == baseFont.pointSize {
            let fallbackCTFont = fallbackFont as CTFont
            if supports(text, font: fallbackCTFont) {
                cacheFont(fallbackCTFont, for: cacheKey)
                return fallbackCTFont
            }
        }

        let fallbackFont = CTFontCreateForString(baseCTFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
        cacheFont(fallbackFont, for: cacheKey)
        return fallbackFont
    }

    private func supports(_ text: String, font: CTFont) -> Bool {
        guard !text.isEmpty else {
            return true
        }

        let cacheKey = "\(CTFontCopyPostScriptName(font))|\(text)"
        if let cachedSupport = supportCache[cacheKey] {
            return cachedSupport
        }

        let codeUnits = Array(text.utf16).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: codeUnits.count)
        let mapped = codeUnits.withUnsafeBufferPointer { codeUnitBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(font, codeUnitBuffer.baseAddress!, glyphBuffer.baseAddress!, codeUnitBuffer.count)
            }
        }
        let isSupported = mapped && glyphs.allSatisfy { $0 != 0 }
        cacheSupport(isSupported, for: cacheKey)
        return isSupported
    }

    private func cacheFont(_ font: CTFont, for key: String) {
        if fontCache.count >= Self.maximumCacheEntries {
            fontCache.removeAll(keepingCapacity: true)
        }
        fontCache[key] = font
    }

    private func cacheSupport(_ isSupported: Bool, for key: String) {
        if supportCache.count >= Self.maximumCacheEntries {
            supportCache.removeAll(keepingCapacity: true)
        }
        supportCache[key] = isSupported
    }

    private static func measurementGlyph(for font: CTFont) -> CGGlyph {
        var character: UniChar = 87
        var glyph = CGGlyph()
        _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        return glyph
    }

    private static func preferredInstalledFontNames() -> [String] {
        let explicitNames = [
            "MesloLGS NF",
            "MesloLGS NF Regular",
            "JetBrainsMono Nerd Font",
            "JetBrains Mono Nerd Font",
            "JetBrains Mono NL",
            "Hack Nerd Font",
            "FiraCode Nerd Font",
            "Fira Code Nerd Font",
            "CaskaydiaCove Nerd Font",
            "SauceCodePro Nerd Font",
            "Monaspace Neon",
            "Menlo",
        ]
        let discoveredNames = NSFontManager.shared.availableFontFamilies.filter { name in
            let normalized = name.lowercased()
            return normalized.contains("nerd font") ||
                normalized.contains("meslo") ||
                normalized.contains("jetbrains mono") ||
                normalized.contains("fira code") ||
                normalized.contains("hack")
        }

        return (explicitNames + discoveredNames).uniqued()
    }

    private static func makeFallbackFonts(size: CGFloat) -> [NSFont] {
        preferredInstalledFontNames().compactMap { NSFont(name: $0, size: size) }
    }

    private static func logFontDiagnostics(font: NSFont) {
        let powerline = "\u{E0B0}"
        let supportsPowerline = Self.staticSupports(powerline, font: font as CTFont)
        NSLog(
            "GhostNotch terminal font: \(font.fontName) family=\(font.familyName ?? "unknown") supportsPowerline=\(supportsPowerline)"
        )
    }

    private static func staticSupports(_ text: String, font: CTFont) -> Bool {
        guard !text.isEmpty else {
            return true
        }

        let codeUnits = Array(text.utf16).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: codeUnits.count)
        let mapped = codeUnits.withUnsafeBufferPointer { codeUnitBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(font, codeUnitBuffer.baseAddress!, glyphBuffer.baseAddress!, codeUnitBuffer.count)
            }
        }
        return mapped && glyphs.allSatisfy { $0 != 0 }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

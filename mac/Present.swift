import AppKit
import LensTransLogic

// Decision helpers live in Logic/PureLogic.swift (LensTransLogic).

enum MacPresentMode {
    case immersive
    case sticker
    case stickerContrast

    init(_ logic: PresentModeLogic) {
        switch logic {
        case .immersive: self = .immersive
        case .sticker: self = .sticker
        case .stickerContrast: self = .stickerContrast
        }
    }
}

struct MacPresentBlock {
    var rect: CGRect
    var mode: MacPresentMode
    var text: String
    var source: String?
    var fill: NSColor
    var textColor: NSColor
    var stickerAlpha: CGFloat
    var fontSize: CGFloat = 0
    var fontWeight: Int = 400
    var lineHeight: CGFloat = 0
    var centerTextVertically = true
    var coverRects: [CGRect] = []
    var textInset = CGSize(width: 3, height: 2)
    var cornerRadius: CGFloat = 2
}

enum MacPresent {
    static let immersiveVariance: Float = PresentLogic.immersiveVariance
    static let wcagAa: Double = PresentLogic.wcagAa
    static let sourceFontRatio: CGFloat = 0.6

    static func decide(bgVariance: Float, contrast: Bool, lock: String) -> MacPresentMode {
        MacCoreBridge.presentMode(backgroundVariance: bgVariance, contrast: contrast,
                                  render: lock)
    }

    static func fadeAlpha(hasText: Bool, emptyMs: Int, fadeMs: Int = 200) -> Float {
        PresentLogic.fadeAlpha(hasText: hasText, emptyMs: emptyMs, fadeMs: fadeMs)
    }

    static func ensureAaColor(tr: inout Int, tg: inout Int, tb: inout Int, br: Int, bg: Int, bb: Int) {
        PresentLogic.ensureAaColor(tr: &tr, tg: &tg, tb: &tb, br: br, bg: bg, bb: bb)
    }

    /// Draw decision into a layer: solid fill (immersive) or opaque sticker bar.
    /// Never draws translucent text over still-visible source.
    static func paint(mode: MacPresentMode, text: String, source: String?,
                      fill: NSColor, textColor: NSColor, stickerAlpha: CGFloat,
                      in bounds: CGRect, ctx: CGContext, maxFont: CGFloat? = nil,
                      fontWeight: Int = 400, lineHeight: CGFloat = 0,
                      centerTextVertically: Bool = true,
                      coverRects: [CGRect] = [],
                      textInset: CGSize = CGSize(width: 3, height: 2),
                      cornerRadius: CGFloat = 2) {
        guard bounds.width > 2, bounds.height > 2 else { return }
        ctx.saveGState()
        if mode == .immersive {
            ctx.clip(to: bounds)
        } else {
            let rounded = CGPath(roundedRect: bounds, cornerWidth: cornerRadius,
                                 cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(rounded)
            ctx.clip()
        }
        defer { ctx.restoreGState() }

        var tr = Int((textColor.usingColorSpace(.deviceRGB)?.redComponent ?? 0) * 255)
        var tg = Int((textColor.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) * 255)
        var tb = Int((textColor.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) * 255)
        let br = Int((fill.usingColorSpace(.deviceRGB)?.redComponent ?? 0) * 255)
        let bg = Int((fill.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) * 255)
        let bb = Int((fill.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) * 255)
        ensureAaColor(tr: &tr, tg: &tg, tb: &tb, br: br, bg: bg, bb: bb)
        let safeText = NSColor(calibratedRed: CGFloat(tr) / 255, green: CGFloat(tg) / 255,
                               blue: CGFloat(tb) / 255, alpha: 1)

        let targetRect: CGRect
        let sourceRect: CGRect?
        if mode == .stickerContrast, let source, !source.isEmpty, bounds.height >= 30 {
            let sourceHeight = max(12, bounds.height * 0.28)
            targetRect = CGRect(x: bounds.minX, y: bounds.minY,
                                width: bounds.width, height: bounds.height - sourceHeight)
            sourceRect = CGRect(x: bounds.minX, y: targetRect.maxY,
                                width: bounds.width, height: sourceHeight)
        } else {
            targetRect = bounds
            sourceRect = nil
        }
        switch mode {
        case .immersive:
            ctx.setFillColor(fill.withAlphaComponent(1).cgColor)
            let masks = coverRects.isEmpty ? [bounds] : coverRects
            for mask in masks {
                let clipped = mask.intersection(bounds)
                if !clipped.isNull { ctx.fill(clipped) }
            }
            drawString(text, color: safeText, in: targetRect, ctx: ctx, maxFont: maxFont,
                       fontWeight: fontWeight, lineHeight: lineHeight,
                       centerVertically: centerTextVertically, textInset: textInset)
        case .sticker, .stickerContrast:
            _ = stickerAlpha
            ctx.setFillColor(fill.withAlphaComponent(1).cgColor)
            ctx.fill(bounds)
            drawString(text, color: safeText, in: targetRect, ctx: ctx, maxFont: maxFont,
                       fontWeight: fontWeight, lineHeight: lineHeight,
                       centerVertically: centerTextVertically, textInset: textInset)
            if let sourceRect, let source, !source.isEmpty {
                drawSourceString(source, color: safeText.withAlphaComponent(0.72),
                                 in: sourceRect, ctx: ctx,
                                 maxFont: max(1, min(maxFont ?? 10, sourceRect.height * 0.42)))
            }
        }
    }

    private static func drawSourceString(_ text: String, color: NSColor, in rect: CGRect,
                                         ctx: CGContext, maxFont: CGFloat) {
        let drawRect = rect.insetBy(dx: min(2, rect.width * 0.04),
                                    dy: min(1, rect.height * 0.06))
        guard drawRect.width > 1, drawRect.height > 1 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byCharWrapping
        var size = max(1, maxFont)
        var attrs = attributes(fontSize: size, weight: 400, color: color,
                               paragraph: paragraph)
        while size > 1 {
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: drawRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            if measured.height <= drawRect.height + 0.5 { break }
            size = max(1, size - 0.5)
            attrs = attributes(fontSize: size, weight: 400, color: color,
                               paragraph: paragraph)
        }
        let value = NSAttributedString(string: text, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        value.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawString(_ s: String, color: NSColor, in rect: CGRect,
                                   ctx: CGContext, maxFont: CGFloat? = nil,
                                   fontWeight: Int = 400,
                                   lineHeight: CGFloat = 0,
                                   centerVertically: Bool = true,
                                   textInset: CGSize = CGSize(width: 3, height: 2)) {
        var drawRect = rect.insetBy(dx: min(textInset.width, rect.width * 0.08),
                                    dy: min(textInset.height, rect.height * 0.10))
        _ = lineHeight
        guard drawRect.width > 1, drawRect.height > 1 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 0
        var size = max(1, min(maxFont ?? 36, drawRect.height))
        var attrs = attributes(fontSize: size, weight: fontWeight,
                               color: color, paragraph: paragraph)
        while size > 1 {
            let measured = (s as NSString).boundingRect(
                with: CGSize(width: drawRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            if measured.height <= drawRect.height + 0.5 { break }
            size = max(1, size - 0.5)
            attrs = attributes(fontSize: size, weight: fontWeight,
                               color: color, paragraph: paragraph)
        }
        let ns = NSAttributedString(string: s, attributes: attrs)
        let measured = (s as NSString).boundingRect(
            with: CGSize(width: drawRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        if centerVertically, measured.height < drawRect.height {
            drawRect.origin.y += (drawRect.height - measured.height) / 2
            drawRect.size.height = measured.height
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ns.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func attributes(fontSize: CGFloat, weight: Int, color: NSColor,
                                   paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        let nativeWeight: NSFont.Weight = weight >= 600 ? .semibold : .regular
        let font = NSFont.systemFont(ofSize: max(1, fontSize), weight: nativeWeight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        return attrs
    }
}

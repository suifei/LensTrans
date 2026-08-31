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
                      in bounds: CGRect, ctx: CGContext, maxFont: CGFloat? = nil) {
        guard bounds.width > 2, bounds.height > 2 else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
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
            ctx.fill(bounds)
            drawString(text, color: safeText, in: targetRect, ctx: ctx, maxFont: maxFont)
        case .sticker, .stickerContrast:
            let a = min(1, max(0.6, stickerAlpha))
            ctx.setFillColor(fill.withAlphaComponent(a).cgColor)
            ctx.fill(bounds)
            drawString(text, color: safeText, in: targetRect, ctx: ctx, maxFont: maxFont)
            if let sourceRect, let source, !source.isEmpty {
                drawString(source, color: safeText.withAlphaComponent(0.8),
                           in: sourceRect, ctx: ctx, maxFont: max(9, sourceRect.height * 0.62))
            }
        }
    }

    private static func drawString(_ s: String, color: NSColor, in rect: CGRect,
                                   ctx: CGContext, maxFont: CGFloat? = nil) {
        let drawRect = rect.insetBy(dx: min(5, rect.width * 0.08),
                                    dy: min(3, rect.height * 0.10))
        guard drawRect.width > 1, drawRect.height > 1 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 0
        let upper = max(8, min(maxFont ?? 36, drawRect.height * 0.82))
        var size = upper
        var attrs: [NSAttributedString.Key: Any] = [:]
        while size > 8 {
            attrs = attributes(fontSize: size, color: color, paragraph: paragraph)
            let measured = (s as NSString).boundingRect(
                with: CGSize(width: drawRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            if measured.height <= drawRect.height + 0.5 { break }
            size -= 0.5
        }
        if attrs.isEmpty {
            attrs = attributes(fontSize: 8, color: color, paragraph: paragraph)
        }
        let ns = NSAttributedString(string: s, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ns.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func attributes(fontSize: CGFloat, color: NSColor,
                                   paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        let font = NSFont.systemFont(ofSize: max(8, fontSize), weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        return attrs
    }
}

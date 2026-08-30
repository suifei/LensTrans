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

enum MacPresent {
    static let immersiveVariance: Float = PresentLogic.immersiveVariance
    static let wcagAa: Double = PresentLogic.wcagAa
    static let sourceFontRatio: CGFloat = 0.6

    static func decide(bgVariance: Float, contrast: Bool, lock: String) -> MacPresentMode {
        MacPresentMode(PresentLogic.decide(bgVariance: bgVariance, contrast: contrast, lock: lock))
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
                      in bounds: CGRect, ctx: CGContext) {
        var tr = Int((textColor.usingColorSpace(.deviceRGB)?.redComponent ?? 0) * 255)
        var tg = Int((textColor.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) * 255)
        var tb = Int((textColor.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) * 255)
        let br = Int((fill.usingColorSpace(.deviceRGB)?.redComponent ?? 0) * 255)
        let bg = Int((fill.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) * 255)
        let bb = Int((fill.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) * 255)
        ensureAaColor(tr: &tr, tg: &tg, tb: &tb, br: br, bg: bg, bb: bb)
        let safeText = NSColor(calibratedRed: CGFloat(tr) / 255, green: CGFloat(tg) / 255,
                               blue: CGFloat(tb) / 255, alpha: 1)

        switch mode {
        case .immersive:
            ctx.setFillColor(fill.withAlphaComponent(1).cgColor)
            ctx.fill(bounds)
            drawString(text, color: safeText, fontSize: bounds.height * 0.55, in: bounds, ctx: ctx)
        case .sticker, .stickerContrast:
            let a = min(1, max(0.6, stickerAlpha))
            ctx.setFillColor(fill.withAlphaComponent(a).cgColor)
            ctx.fill(bounds)
            drawString(text, color: safeText, fontSize: bounds.height * 0.55, in: bounds, ctx: ctx)
            if mode == .stickerContrast, let source, !source.isEmpty {
                let sub = bounds.insetBy(dx: 2, dy: bounds.height * 0.55)
                drawString(source, color: safeText.withAlphaComponent(0.85),
                           fontSize: bounds.height * sourceFontRatio * 0.45, in: sub, ctx: ctx)
            }
        }
    }

    private static func drawString(_ s: String, color: NSColor, fontSize: CGFloat,
                                   in rect: CGRect, ctx: CGContext) {
        let font = NSFont.systemFont(ofSize: max(9, fontSize))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ns = NSAttributedString(string: s, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ns.draw(in: rect.insetBy(dx: 4, dy: 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

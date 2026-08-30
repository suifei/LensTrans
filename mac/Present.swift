import AppKit

// Immersive fill / sticker / sticker+contrast. No transparent-over-source text.

enum MacPresentMode {
    case immersive
    case sticker
    case stickerContrast
}

enum MacPresent {
    static func decide(bgVariance: Float, contrast: Bool, lock: String) -> MacPresentMode {
        if lock == "sticker" { return contrast ? .stickerContrast : .sticker }
        if lock == "immersive" { return .immersive }
        if bgVariance < 18 { return .immersive }
        return contrast ? .stickerContrast : .sticker
    }

    static func fadeAlpha(hasText: Bool, emptyMs: Int, fadeMs: Int = 200) -> Float {
        if hasText { return 1 }
        if emptyMs <= 0 { return 1 }
        if emptyMs >= fadeMs { return 0 }
        return 1 - Float(emptyMs) / Float(fadeMs)
    }
}

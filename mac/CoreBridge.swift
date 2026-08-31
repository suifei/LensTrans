import Foundation
import LlamaBridge

// The only Swift-facing translation/layout policy lives in core. This adapter keeps C ABI
// ownership explicit: all strings are borrowed for one call and all results are copied out.
enum MacCoreBridge {
    enum EngineKind: Sendable {
        case none
        case local
        case cloud
    }

    struct Layout {
        var rect: CGRect
        var fontSize: CGFloat
        var lineHeight: CGFloat
        var mode: MacPresentMode
        var coversSource: Bool
        var showSource: Bool
        var textColor: (red: CGFloat, green: CGFloat, blue: CGFloat)
        var fillColor: (red: CGFloat, green: CGFloat, blue: CGFloat)
    }

    static func route(preference: String, privacy: Bool, textCharacters: Int,
                      localReady: Bool, cloudReady: Bool) -> EngineKind {
        let pref: Int32
        switch preference {
        case "local": pref = Int32(LT_ENGINE_LOCAL)
        case "cloud": pref = Int32(LT_ENGINE_CLOUD)
        default: pref = Int32(LT_ENGINE_AUTO)
        }
        let result = lenstrans_core_route(pref, privacy ? 1 : 0, textCharacters,
                                          localReady ? 1 : 0, cloudReady ? 1 : 0)
        switch result {
        case Int32(LT_ENGINE_KIND_LOCAL): return .local
        case Int32(LT_ENGINE_KIND_CLOUD): return .cloud
        default: return .none
        }
    }

    static func presentMode(backgroundVariance: Float, contrast: Bool,
                            render: String) -> MacPresentMode {
        let lock: Int32 = render == "sticker" ? 1 : render == "immersive" ? 2 : 0
        let raw = lenstrans_core_present_mode(backgroundVariance, contrast ? 1 : 0, lock)
        switch raw {
        case Int32(LT_PRESENT_STICKER): return .sticker
        case Int32(LT_PRESENT_STICKER_CONTRAST): return .stickerContrast
        default: return .immersive
        }
    }

    static func layout(block: MacOcrBlock, translation: String, frameSize: CGSize,
                       targetSize: CGSize, contrast: Bool, render: String,
                       stickerAlpha: Int, fontScale: Int) -> Layout? {
        guard frameSize.width > 0, frameSize.height > 0,
              targetSize.width > 0, targetSize.height > 0,
              !block.text.isEmpty, !translation.isEmpty else { return nil }

        var input = LenstransCoreBlock()
        var output = LenstransCoreLayout()
        input.x = block.x
        input.y = block.y
        input.width = block.w
        input.height = block.h
        input.line_height = block.lineHeight
        input.red = block.r
        input.green = block.g
        input.blue = block.b
        input.background_red = block.r
        input.background_green = block.g
        input.background_blue = block.b
        input.background_variance = block.bgVariance

        let lock: Int32
        switch render {
        case "sticker": lock = 1
        case "immersive": lock = 2
        default: lock = 0
        }
        let ok = block.text.withCString { source in
            input.text = source
            return translation.withCString { translated in
                lenstrans_core_layout_block(
                    &input, translated,
                    Int32(max(1, Int(frameSize.width.rounded()))),
                    Int32(max(1, Int(frameSize.height.rounded()))),
                    Int32(max(1, Int(targetSize.width.rounded()))),
                    Int32(max(1, Int(targetSize.height.rounded()))),
                    contrast ? 1 : 0, lock, Int32(stickerAlpha), Int32(fontScale), &output
                )
            }
        }
        guard ok != 0 else { return nil }
        let mode: MacPresentMode
        switch output.mode {
        case Int32(LT_PRESENT_STICKER): mode = .sticker
        case Int32(LT_PRESENT_STICKER_CONTRAST): mode = .stickerContrast
        default: mode = .immersive
        }
        return Layout(
            rect: CGRect(x: CGFloat(output.x), y: CGFloat(output.y),
                         width: CGFloat(output.width), height: CGFloat(output.height)),
            fontSize: CGFloat(output.font_px), lineHeight: CGFloat(output.line_height_px),
            mode: mode, coversSource: output.covers_source != 0, showSource: output.show_source != 0,
            textColor: (CGFloat(output.text_red) / 255, CGFloat(output.text_green) / 255,
                        CGFloat(output.text_blue) / 255),
            fillColor: (CGFloat(output.fill_red) / 255, CGFloat(output.fill_green) / 255,
                        CGFloat(output.fill_blue) / 255)
        )
    }

    static func prompt(text: String, sourceLanguage: String = "auto", targetLanguage: String) -> String? {
        var output = [CChar](repeating: 0, count: 16 * 1024)
        let ok = text.withCString { source in
            sourceLanguage.withCString { src in
                targetLanguage.withCString { target in
                    lenstrans_core_build_prompt(source, src, target, &output, output.count)
                }
            }
        }
        guard ok != 0 else { return nil }
        return String(cString: output)
    }
}

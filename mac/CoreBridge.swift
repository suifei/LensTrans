import AppKit
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
        var text: String
        var sourceText: String
        var sourceLineHeight: CGFloat
        var coverRects: [CGRect]
        var fontSize: CGFloat
        var fontWeight: Int
        var lineHeight: CGFloat
        var textInset: CGSize
        var cornerRadius: CGFloat
        var mode: MacPresentMode
        var coversSource: Bool
        var showSource: Bool
        var centerTextVertically: Bool
        var textColor: (red: CGFloat, green: CGFloat, blue: CGFloat)
        var fillColor: (red: CGFloat, green: CGFloat, blue: CGFloat)
    }

    enum UiActivity: Int32 {
        case hidden = 0, stopped = 1, active = 2, paused = 3
    }

    enum UiInput: Int32 {
        case rightClick = 1, leftDoubleClick = 2, start = 3, stop = 4
        case pause = 5, resume = 6, hide = 7, show = 8
        case setOverlay = 9, setBilingual = 10
    }

    struct UiState {
        var activity: UiActivity
        var bilingual: Bool
    }

    struct UiVisual {
        var border: NSColor
        var fillAlpha: CGFloat
        var showResizeHandles: Bool
        var showCornerMarkers: Bool
    }

    static func uiTransition(_ state: UiState, input: UiInput) -> UiState? {
        var source = LenstransCoreUiState(
            activity: state.activity.rawValue,
            presentation: state.bilingual ? Int32(LT_UI_BILINGUAL) : Int32(LT_UI_OVERLAY))
        var output = LenstransCoreUiState()
        guard lenstrans_core_ui_transition(&source, input.rawValue, &output) != 0,
              let activity = UiActivity(rawValue: output.activity) else { return nil }
        return UiState(activity: activity, bilingual: output.presentation == LT_UI_BILINGUAL)
    }

    static func uiVisual(_ state: UiState) -> UiVisual? {
        var source = LenstransCoreUiState(
            activity: state.activity.rawValue,
            presentation: state.bilingual ? Int32(LT_UI_BILINGUAL) : Int32(LT_UI_OVERLAY))
        var output = LenstransCoreUiVisual()
        guard lenstrans_core_ui_visual(&source, &output) != 0 else { return nil }
        return UiVisual(
            border: NSColor(calibratedRed: CGFloat(output.border_red) / 255,
                            green: CGFloat(output.border_green) / 255,
                            blue: CGFloat(output.border_blue) / 255, alpha: 1),
            fillAlpha: CGFloat(output.editing_fill_alpha),
            showResizeHandles: output.show_resize_handles != 0,
            showCornerMarkers: output.show_corner_markers != 0)
    }

    static func uiHitTest(point: CGPoint, size: CGSize, handle: CGFloat,
                          resizeHandles: Bool) -> Int32 {
        Int32(lenstrans_core_ui_hit_test(
            Float(point.x), Float(point.y), Float(size.width), Float(size.height),
            Float(handle), resizeHandles ? 1 : 0))
    }

    static func uiDrag(start: CGRect, anchor: Int32, dx: CGFloat, dy: CGFloat,
                       minSize: CGSize) -> CGRect? {
        var x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0
        guard lenstrans_core_ui_drag(
            Float(start.minX), Float(start.minY), Float(start.width), Float(start.height),
            anchor, Float(dx), Float(dy), Float(minSize.width), Float(minSize.height),
            &x, &y, &width, &height) != 0 else { return nil }
        return CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    static func batchSource(blocks: [MacOcrBlock]) -> String? {
        guard let batch = lenstrans_core_batch_create() else { return nil }
        defer { lenstrans_core_batch_destroy(batch) }
        for block in blocks {
            let ok = block.text.withCString {
                lenstrans_core_batch_add(batch, $0, block.x, block.y, block.w, block.h)
            }
            guard ok != 0 else { return nil }
        }
        var output = [CChar](repeating: 0, count: 256 * 1024)
        guard lenstrans_core_batch_source(batch, &output, output.count) != 0 else { return nil }
        return String(cString: output)
    }

    static func batchPrompt(source: String, sourceLanguage: String,
                            targetLanguage: String, chatWrapped: Bool) -> String? {
        var output = [CChar](repeating: 0, count: 320 * 1024)
        let ok = source.withCString { sourcePtr in
            sourceLanguage.withCString { sourceLanguagePtr in
                targetLanguage.withCString { targetPtr in
                    if chatWrapped {
                        return lenstrans_core_batch_chat_prompt(
                            sourcePtr, sourceLanguagePtr, targetPtr, &output, output.count)
                    }
                    return lenstrans_core_batch_user_prompt(
                        sourcePtr, sourceLanguagePtr, targetPtr, &output, output.count)
                }
            }
        }
        return ok != 0 ? String(cString: output) : nil
    }

    static func parseBatch(output: String, count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            var item = [CChar](repeating: 0, count: 16 * 1024)
            let ok = output.withCString {
                lenstrans_core_batch_parse_item($0, count, index, &item, item.count)
            }
            return ok != 0 ? String(cString: item) : ""
        }
    }

    static func batchOutputUsable(blocks: [MacOcrBlock], output: String,
                                  targetLanguage: String) -> Bool {
        guard let batch = lenstrans_core_batch_create() else { return false }
        defer { lenstrans_core_batch_destroy(batch) }
        for block in blocks {
            let ok = block.text.withCString {
                lenstrans_core_batch_add(batch, $0, block.x, block.y, block.w, block.h)
            }
            if ok == 0 { return false }
        }
        return output.withCString { outputPtr in
            targetLanguage.withCString {
                lenstrans_core_batch_output_usable(batch, outputPtr, $0) != 0
            }
        }
    }

    static func translationUsable(source: String, translation: String,
                                  targetLanguage: String) -> Bool {
        source.withCString { sourcePtr in
            translation.withCString { translationPtr in
                targetLanguage.withCString { targetPtr in
                    lenstrans_core_translation_usable(sourcePtr, translationPtr, targetPtr) != 0
                }
            }
        }
    }

    static func sourceNeedsTranslation(_ source: String, targetLanguage: String) -> Bool {
        source.withCString { sourcePtr in
            targetLanguage.withCString { targetPtr in
                lenstrans_core_source_needs_translation(sourcePtr, targetPtr) != 0
            }
        }
    }

    static var batchFallbackGroupSize: Int {
        max(1, Int(lenstrans_core_batch_fallback_group_size()))
    }

    static func batchFallbackUsable(totalGroups: Int, usableGroups: Int) -> Bool {
        lenstrans_core_batch_fallback_usable(totalGroups, usableGroups) != 0
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
                       stickerAlpha: Int, fontScale: Int,
                       targetPixelsPerUnit: CGFloat) -> Layout? {
        guard frameSize.width > 0, frameSize.height > 0,
              targetSize.width > 0, targetSize.height > 0,
              !block.text.isEmpty, !translation.isEmpty else { return nil }

        var input = coreBlock(block)
        var output = LenstransCoreLayout()
        var wrapped = [CChar](repeating: 0, count: 16 * 1024)

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
                    contrast ? 1 : 0, lock, Int32(stickerAlpha), Int32(fontScale),
                    Float(targetPixelsPerUnit), &output, &wrapped, wrapped.count
                )
            }
        }
        guard ok != 0 else { return nil }
        return decodeLayout(output, wrapped: wrapped, source: block.text)
    }

    static func layouts(blocks: [MacOcrBlock], translations: [String],
                        frameSize: CGSize, targetSize: CGSize, contrast: Bool,
                        render: String, stickerAlpha: Int, fontScale: Int,
                        targetPixelsPerUnit: CGFloat) -> [Layout] {
        guard !blocks.isEmpty, blocks.count == translations.count,
              frameSize.width > 0, frameSize.height > 0,
              targetSize.width > 0, targetSize.height > 0 else { return [] }
        let lock: Int32 = render == "sticker" ? 1 : render == "immersive" ? 2 : 0
        guard let batch = lenstrans_core_present_batch_create(
            Int32(max(1, Int(frameSize.width.rounded()))),
            Int32(max(1, Int(frameSize.height.rounded()))),
            Int32(max(1, Int(targetSize.width.rounded()))),
            Int32(max(1, Int(targetSize.height.rounded()))),
            contrast ? 1 : 0, lock, Int32(stickerAlpha), Int32(fontScale),
            Float(targetPixelsPerUnit)) else { return [] }
        defer { lenstrans_core_present_batch_destroy(batch) }
        for index in blocks.indices {
            var input = coreBlock(blocks[index])
            let added = blocks[index].text.withCString { source in
                input.text = source
                return translations[index].withCString { translated in
                    lenstrans_core_present_batch_add(batch, &input, translated)
                }
            }
            if added == 0 { return [] }
            for mask in blocks[index].masks {
                _ = lenstrans_core_present_batch_add_mask(
                    batch, Float(mask.minX), Float(mask.minY),
                    Float(mask.width), Float(mask.height))
            }
        }
        let count = Int(lenstrans_core_present_batch_build(batch))
        var result: [Layout] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            var output = LenstransCoreLayout()
            var wrapped = [CChar](repeating: 0, count: 16 * 1024)
            var source = [CChar](repeating: 0, count: 16 * 1024)
            let ok = lenstrans_core_present_batch_get(
                batch, index, &output, &wrapped, wrapped.count, &source, source.count)
            if ok != 0 {
                var covers: [CGRect] = []
                let coverCount = Int(lenstrans_core_present_batch_cover_count(batch, index))
                covers.reserveCapacity(coverCount)
                for coverIndex in 0..<coverCount {
                    var x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0
                    if lenstrans_core_present_batch_cover_get(
                        batch, index, coverIndex, &x, &y, &width, &height) != 0 {
                        covers.append(CGRect(x: CGFloat(x), y: CGFloat(y),
                                             width: CGFloat(width), height: CGFloat(height)))
                    }
                }
                result.append(decodeLayout(output, wrapped: wrapped,
                                           source: String(cString: source), coverRects: covers))
            }
        }
        return result
    }

    private static func coreBlock(_ block: MacOcrBlock) -> LenstransCoreBlock {
        var input = LenstransCoreBlock()
        input.x = block.x; input.y = block.y
        input.width = block.w; input.height = block.h
        input.line_height = block.lineHeight
        input.red = block.r; input.green = block.g; input.blue = block.b
        input.background_red = block.r
        input.background_green = block.g
        input.background_blue = block.b
        input.background_variance = block.bgVariance
        return input
    }

    private static func decodeLayout(_ output: LenstransCoreLayout,
                                     wrapped: [CChar], source: String,
                                     coverRects: [CGRect] = []) -> Layout {
        let mode: MacPresentMode
        switch output.mode {
        case Int32(LT_PRESENT_STICKER): mode = .sticker
        case Int32(LT_PRESENT_STICKER_CONTRAST): mode = .stickerContrast
        default: mode = .immersive
        }
        let rect = CGRect(x: CGFloat(output.x), y: CGFloat(output.y),
                          width: CGFloat(output.width), height: CGFloat(output.height))
        return Layout(
            rect: rect,
            text: String(cString: wrapped),
            sourceText: source,
            sourceLineHeight: CGFloat(output.source_line_height),
            coverRects: coverRects.isEmpty ? [rect] : coverRects,
            fontSize: CGFloat(output.font_px), fontWeight: Int(output.font_weight),
            lineHeight: CGFloat(output.line_height_px),
            textInset: CGSize(width: CGFloat(output.text_inset_x),
                              height: CGFloat(output.text_inset_y)),
            cornerRadius: CGFloat(output.corner_radius),
            mode: mode, coversSource: output.covers_source != 0, showSource: output.show_source != 0,
            centerTextVertically: output.center_text_vertically != 0,
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

    static func outputTokenBudget(text: String, batchProtocol: Bool, quality: Bool) -> Int {
        text.withCString {
            Int(lenstrans_core_output_token_budget($0, batchProtocol ? 1 : 0, quality ? 1 : 0))
        }
    }

    static func localEnginePrompt(text: String, sourceLanguage: String,
                                  targetLanguage: String, batchProtocol: Bool,
                                  modelPath: String) -> String? {
        var output = [CChar](repeating: 0, count: 32 * 1024)
        let ok = text.withCString { textPtr in
            sourceLanguage.withCString { sourcePtr in
                targetLanguage.withCString { targetPtr in
                    modelPath.withCString { modelPtr in
                        lenstrans_core_build_local_engine_prompt(
                            textPtr, sourcePtr, targetPtr, batchProtocol ? 1 : 0,
                            modelPtr, &output, output.count)
                    }
                }
            }
        }
        return ok != 0 ? String(cString: output) : nil
    }

    static func isHunyuanModel(path: String) -> Bool {
        path.withCString { lenstrans_core_is_hunyuan_model_path($0) != 0 }
    }
}

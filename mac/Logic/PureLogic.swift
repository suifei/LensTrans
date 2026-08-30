import Foundation

// Pure Foundation logic shared by macOS app + Linux/macOS `swift test`.
// Keep AppKit out of this file so CI without Cocoa can still verify invariants.

public enum PresentModeLogic: String, Equatable {
    case immersive
    case sticker
    case stickerContrast
}

public enum PresentLogic {
    public static let immersiveVariance: Float = 18
    public static let wcagAa: Double = 4.5

    public static func decide(bgVariance: Float, contrast: Bool, lock: String) -> PresentModeLogic {
        if lock == "sticker" { return contrast ? .stickerContrast : .sticker }
        if lock == "immersive" { return .immersive }
        if bgVariance < immersiveVariance { return .immersive }
        return contrast ? .stickerContrast : .sticker
    }

    public static func fadeAlpha(hasText: Bool, emptyMs: Int, fadeMs: Int = 200) -> Float {
        if hasText { return 1 }
        if emptyMs <= 0 { return 1 }
        if emptyMs >= fadeMs { return 0 }
        return 1 - Float(emptyMs) / Float(fadeMs)
    }

    public static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }

    public static func contrastRatio(tr: Int, tg: Int, tb: Int, br: Int, bg: Int, bb: Int) -> Double {
        let l1 = relativeLuminance(r: tr, g: tg, b: tb)
        let l2 = relativeLuminance(r: br, g: bg, b: bb)
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    public static func ensureAaColor(tr: inout Int, tg: inout Int, tb: inout Int, br: Int, bg: Int, bb: Int) {
        if contrastRatio(tr: tr, tg: tg, tb: tb, br: br, bg: bg, bb: bb) >= wcagAa { return }
        tr = 255 - br
        tg = 255 - bg
        tb = 255 - bb
    }
}

public enum CloudParseLogic {
    public static func parseChatCompletion(_ body: String) -> String {
        if body.contains("data:") {
            var out = ""
            for line in body.split(whereSeparator: \.isNewline) {
                var s = String(line)
                if s.hasPrefix("data:") {
                    s = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                if s == "[DONE]" || s.isEmpty { continue }
                if let chunk = extractDelta(s) { out += chunk }
            }
            return out
        }
        return extractMessage(body) ?? ""
    }

    private static func extractDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any], let c = delta["content"] as? String { return c }
        if let msg = first["message"] as? [String: Any], let c = msg["content"] as? String { return c }
        return nil
    }

    private static func extractMessage(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let c = msg["content"] as? String else { return nil }
        return c
    }
}

public enum EngineRouteLogic {
    public enum Kind: String { case none, local, cloud }
    public static func route(pref: String, privacy: Bool, chars: Int, localOk: Bool, cloudOk: Bool) -> Kind {
        if privacy { return localOk ? .local : .none }
        if pref == "local" { return localOk ? .local : .none }
        if pref == "cloud" { return cloudOk ? .cloud : (localOk ? .local : .none) }
        if chars > 200 && cloudOk { return .cloud }
        if localOk { return .local }
        if cloudOk { return .cloud }
        return .none
    }
}

public enum ModelMetaLogic {
    public static let ggufBytes: UInt64 = 491400032
    public static let ggufSha256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
    public static let fileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    public static let idleUnloadMs: Int64 = 10 * 60 * 1000

    public static func sha256Matches(_ hex: String) -> Bool {
        hex.lowercased() == ggufSha256
    }
}

public enum LocalPromptLogic {
    public static func buildTranslatePrompt(text: String, tgtLang: String) -> String {
        let user: String
        if tgtLang == "zh" || tgtLang == "zh-CN" {
            user = "英译简体中文。习语按含义意译，勿逐字直译。输出完整且简洁的译文，不要解释。\n\n" + text
        } else {
            let name: String
            switch tgtLang {
            case "en": name = "English"
            case "ja": name = "Japanese"
            case "ko": name = "Korean"
            default: name = tgtLang
            }
            user = "Translate the following segment into \(name), without additional explanation.\n\n" + text
        }
        // ChatML wrap — matches core WrapQwenChat; works with llama-completion -no-cnv.
        return "<|im_start|>system\nYou translate text accurately and concisely. Idioms: translate by "
            + "meaning, not literally. Output only the translation; no explanation."
            + "<|im_end|>\n<|im_start|>user\n" + user + "<|im_end|>\n<|im_start|>assistant\n"
    }

    public static func stripThink(_ raw: String) -> String {
        var s = raw
        if let a = s.range(of: "<think>"), let b = s.range(of: "</think>"), a.lowerBound < b.upperBound {
            s.removeSubrange(a.lowerBound..<b.upperBound)
        }
        for marker in ["[end of text]", "[end of text]\n", "<|im_end|>"] {
            if let r = s.range(of: marker) { s.removeSubrange(r) }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\""))
    }
}

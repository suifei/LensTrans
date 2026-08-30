import Foundation

// Local llama.cpp (Metal) + OpenAI-compatible cloud. Stub. No default gateway.

struct MacTranslateRequest {
    var text: String
    var srcLang: String = "auto"
    var tgtLang: String = "zh"
    var quality: Bool = false
}

struct MacTranslateResult {
    var text: String = ""
    var error: String = ""
    var firstTokenMs: Int = 0
    var latencyMs: Int = 0
    var beamWidth: Int = 1
}

protocol MacEngine {
    var ready: Bool { get }
    func translate(_ req: MacTranslateRequest) -> MacTranslateResult
}

final class MacLocalEngine: MacEngine {
    var ready: Bool { false }
    init(modelPath _: String) {}
    func translate(_: MacTranslateRequest) -> MacTranslateResult {
        var r = MacTranslateResult()
        r.error = "llama.cpp Metal not wired"
        return r
    }
}

final class MacCloudEngine: MacEngine {
    var ready: Bool { false }
    init(baseURL _: String, apiKey _: String, model _: String) {}
    func translate(_: MacTranslateRequest) -> MacTranslateResult {
        var r = MacTranslateResult()
        r.error = "cloud disabled: empty config"
        return r
    }
}

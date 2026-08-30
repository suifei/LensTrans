import Foundation
import LensTransLogic

// Local llama.cpp (Metal) placeholder + OpenAI-compatible cloud via URLSession.
// No default gateway / no prefilled host / key / model.

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
    var fromCache: Bool = false
}

protocol MacEngine: AnyObject {
    var ready: Bool { get }
    func translate(_ req: MacTranslateRequest) -> MacTranslateResult
    func unload()
    func noteActivity()
    func maybeIdleUnload(idleMs: Int64)
}

extension MacEngine {
    func unload() {}
    func noteActivity() {}
    func maybeIdleUnload(idleMs _: Int64) {}
}

final class MacLocalEngine: MacEngine {
    private let modelPath: String
    private var lastActivity = Date()
    /// Metal / llama.cpp process-in wiring lands with Xcode + third_party/llama.cpp Metal build.
    /// Until linked, Ready is false unless a CLI helper is present next to the app.
    private var loaded = false

    var ready: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    init(modelPath: String) { self.modelPath = modelPath }

    func noteActivity() { lastActivity = Date() }

    func unload() { loaded = false }

    func maybeIdleUnload(idleMs: Int64) {
        let limit = idleMs > 0 ? idleMs : Int64(10 * 60 * 1000)
        if Date().timeIntervalSince(lastActivity) * 1000 >= Double(limit) {
            unload()
        }
    }

    func translate(_ req: MacTranslateRequest) -> MacTranslateResult {
        noteActivity()
        var r = MacTranslateResult()
        guard ready else {
            r.error = "local model missing"
            return r
        }
        // Process-in Metal path not linked in this tree (no Xcode target yet).
        r.error = "llama.cpp Metal not linked — build with Xcode + LENSTRANS_WITH_LLAMA Metal"
        return r
    }
}

final class MacCloudEngine: MacEngine {
    private let baseURL: String
    private let apiKey: String
    private let model: String

    var ready: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey
        self.model = model
    }

    func translate(_ req: MacTranslateRequest) -> MacTranslateResult {
        var r = MacTranslateResult()
        let t0 = Date()
        guard ready else {
            r.error = "cloud not configured"
            return r
        }
        var root = baseURL
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: root + "/chat/completions") else {
            r.error = "bad base url"
            return r
        }
        let prompt: String
        if req.tgtLang == "zh" || req.tgtLang == "zh-CN" {
            prompt = "英译简体中文。习语按含义意译，勿逐字直译。输出完整且简洁的译文，不要解释。\n\n" + req.text
        } else {
            prompt = "Translate the following segment into \(req.tgtLang), without additional explanation.\n\n" + req.text
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [["role": "user", "content": prompt]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            r.error = "json encode failed"
            return r
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let sem = DispatchSemaphore(value: 0)
        var acc = ""
        var err = ""
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { sem.signal() }
            if let error { err = error.localizedDescription; return }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                err = "empty cloud output"
                return
            }
            acc = Self.parseChatCompletion(text)
            if acc.isEmpty { err = "empty cloud output" }
        }.resume()
        _ = sem.wait(timeout: .now() + 35)
        r.text = acc
        r.error = err
        r.latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
        return r
    }

    /// OpenAI chat.completion JSON or SSE `data:` lines → concatenated content.
    static func parseChatCompletion(_ body: String) -> String {
        CloudParseLogic.parseChatCompletion(body)
    }
}

enum MacEngineRouter {
    enum Kind { case none, local, cloud }
    static func route(pref: String, privacy: Bool, chars: Int, localOk: Bool, cloudOk: Bool) -> Kind {
        switch EngineRouteLogic.route(pref: pref, privacy: privacy, chars: chars, localOk: localOk, cloudOk: cloudOk) {
        case .none: return .none
        case .local: return .local
        case .cloud: return .cloud
        }
    }
}

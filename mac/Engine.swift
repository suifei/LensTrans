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
    private let cliPath: String?
    private var lastActivity = Date()
    /// Process-in Metal (LENSTRANS_WITH_LLAMA) is not linked in SPM yet.
    /// Runtime path: spawn llama-cli (Homebrew / PATH / third_party) — parity with Windows CliEngine.
    private var loaded = false

    var ready: Bool {
        FileManager.default.fileExists(atPath: modelPath) && cliPath != nil
    }

    init(modelPath: String, cliPath: String? = nil) {
        self.modelPath = modelPath
        self.cliPath = cliPath ?? MacPaths.findLlamaCli()
    }

    func noteActivity() { lastActivity = Date() }

    func unload() { loaded = false }

    func maybeIdleUnload(idleMs: Int64) {
        let limit = idleMs > 0 ? idleMs : ModelMetaLogic.idleUnloadMs
        if Date().timeIntervalSince(lastActivity) * 1000 >= Double(limit) {
            unload()
        }
    }

    func translate(_ req: MacTranslateRequest) -> MacTranslateResult {
        noteActivity()
        var r = MacTranslateResult()
        guard FileManager.default.fileExists(atPath: modelPath) else {
            r.error = "local model missing"
            return r
        }
        guard let cli = cliPath else {
            r.error = "llama-cli not found (install Homebrew llama.cpp or link Metal in-process)"
            return r
        }
        let prompt = LocalPromptLogic.buildTranslatePrompt(
            text: req.text, tgtLang: req.tgtLang)
        let t0 = Date()
        do {
            let out = try Self.runCli(cli: cli, model: modelPath, prompt: prompt)
            r.text = LocalPromptLogic.stripThink(out)
            r.latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            if r.text.isEmpty { r.error = "empty local output" }
        } catch {
            r.error = error.localizedDescription
            r.latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
        }
        return r
    }

    private static func runCli(cli: String, model: String, prompt: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lenstrans-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        // Match win CliEngine flags; --no-display-prompt avoids echoing the prompt into stdout.
        proc.arguments = [
            "-m", model,
            "-f", tmp.path,
            "-n", "96",
            "-c", "1024",
            "--batch-size", "512",
            "-ngl", "99",
            "--temp", "0",
            "-no-cnv",
            "--no-display-prompt",
            "--log-disable",
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()

        let group = DispatchGroup()
        var stdout = Data()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let wait = group.wait(timeout: .now() + 45)
        if wait == .timedOut {
            proc.terminate()
            throw NSError(domain: "LensTrans", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "llama-cli timeout"])
        }
        proc.waitUntilExit()
        return String(data: stdout, encoding: .utf8) ?? ""
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

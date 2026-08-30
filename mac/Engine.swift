import Foundation
import LensTransLogic
import LlamaBridge

// Local llama.cpp Metal in-process (preferred) + OpenAI-compatible cloud via URLSession.
// CLI (llama-completion) is fallback when in-process link/load fails.
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
    /// "metal" | "cli" | "cloud" | ""
    var backend: String = ""
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

/// Thin Swift wrapper over C LlamaBridge (third_party llama.cpp Metal).
enum LlamaInProcess {
    static var available: Bool { lenstrans_llama_available() != 0 }
}

final class MacLocalEngine: MacEngine {
    private let modelPath: String
    private let cliPath: String?
    private var lastActivity = Date()
    private var native: OpaquePointer?
    private let nativeLock = NSLock()

    var ready: Bool {
        FileManager.default.fileExists(atPath: modelPath)
            && (LlamaInProcess.available || cliPath != nil)
    }

    /// True when this build linked Metal llama.cpp and the model file exists.
    var metalReady: Bool {
        LlamaInProcess.available && FileManager.default.fileExists(atPath: modelPath)
    }

    init(modelPath: String, cliPath: String? = nil) {
        self.modelPath = modelPath
        self.cliPath = cliPath ?? MacPaths.findLlamaCli()
    }

    deinit { unload() }

    func noteActivity() { lastActivity = Date() }

    func unload() {
        nativeLock.lock()
        defer { nativeLock.unlock() }
        if let eng = native {
            lenstrans_llama_destroy(eng)
            native = nil
        }
    }

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
        let prompt = LocalPromptLogic.buildTranslatePrompt(
            text: req.text, tgtLang: req.tgtLang)
        let maxNew = req.quality ? 96 : 48

        // 1) Prefer in-process Metal.
        if LlamaInProcess.available {
            if let metal = translateMetal(prompt: prompt, maxNew: maxNew) {
                return metal
            }
        }

        // 2) Fallback: spawn llama-completion / llama-cli.
        guard let cli = cliPath else {
            r.error = LlamaInProcess.available
                ? "in-process Metal failed and llama-completion/llama-cli not found"
                : "llama-completion/llama-cli not found (brew install llama.cpp or fetch-llama-cpp.sh)"
            return r
        }
        let t0 = Date()
        do {
            let out = try Self.runCli(cli: cli, model: modelPath, prompt: prompt)
            r.text = LocalPromptLogic.stripThink(out)
            r.latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            r.backend = "cli"
            if r.text.isEmpty { r.error = "empty local output" }
        } catch {
            r.error = error.localizedDescription
            r.latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            r.backend = "cli"
        }
        return r
    }

    private func ensureNative() -> OpaquePointer? {
        nativeLock.lock()
        defer { nativeLock.unlock() }
        if let eng = native { return eng }
        guard let eng = lenstrans_llama_create(modelPath) else { return nil }
        native = eng
        return eng
    }

    private func translateMetal(prompt: String, maxNew: Int) -> MacTranslateResult? {
        guard let eng = ensureNative() else { return nil }
        var out = [CChar](repeating: 0, count: 8192)
        var err = [CChar](repeating: 0, count: 512)
        var latency: Int32 = 0
        let rc = prompt.withCString { p in
            lenstrans_llama_translate(
                eng, p, Int32(maxNew),
                &out, Int32(out.count),
                &latency,
                &err, Int32(err.count))
        }
        var r = MacTranslateResult()
        r.latencyMs = Int(latency)
        r.backend = "metal"
        if rc != 0 {
            let msg = String(cString: err)
            // Soft-fail → caller may try CLI.
            if msg.isEmpty { return nil }
            // Load/link hard failures: allow CLI fallback.
            if msg.contains("load failed") || msg.contains("not linked") {
                return nil
            }
            r.error = msg
            return r
        }
        r.text = LocalPromptLogic.stripThink(String(cString: out))
        if r.text.isEmpty {
            r.error = "empty local output"
        }
        return r
    }

    private static func runCli(cli: String, model: String, prompt: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lenstrans-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let isCompletion = (cli as NSString).lastPathComponent.contains("completion")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        // Prefer llama-completion + ChatML + -no-cnv (new Homebrew llama-cli is chat-only).
        var args = [
            "-m", model,
            "-f", tmp.path,
            "-n", "96",
            "-c", "1024",
            "--batch-size", "512",
            "-ngl", "99",
            "--temp", "0",
            "-no-cnv",
            "--no-display-prompt",
        ]
        if !isCompletion {
            args.append("--log-disable")
        }
        proc.arguments = args
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
                          userInfo: [NSLocalizedDescriptionKey: "llama-completion timeout"])
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
        r.backend = "cloud"
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

import AppKit
import CommonCrypto
import Foundation

// PRD 4.5: 640×420, 3 steps. Screen-recording step must NOT start SCStream
// (same rule as Windows: do not call ScreenCaptureKit just to probe).

@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 640, height: 420)
    private static var window: NSWindow?
    private static var step = 0
    private static var body: NSTextField?
    private static var localChk: NSButton?
    private static var backBtn: NSButton?
    private static var nextBtn: NSButton?

    static func present() {
        step = 0
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "LensTrans 引导"
        win.center()

        let body = NSTextField(wrappingLabelWithString: "")
        body.frame = NSRect(x: 24, y: 100, width: 592, height: 280)
        OnboardingWindow.body = body

        let local = NSButton(checkboxWithTitle: "使用本地模型（推荐）", target: nil, action: nil)
        local.state = SettingsStore.shared.downloadModel ? .on : .off
        local.frame = NSRect(x: 24, y: 72, width: 280, height: 24)
        local.isHidden = true
        OnboardingWindow.localChk = local

        let back = NSButton(title: "上一步", target: OnbProxy.shared, action: #selector(OnbProxy.back))
        back.frame = NSRect(x: 352, y: 24, width: 80, height: 28)
        back.isEnabled = false
        OnboardingWindow.backBtn = back

        let next = NSButton(title: "下一步", target: OnbProxy.shared, action: #selector(OnbProxy.next))
        next.frame = NSRect(x: 444, y: 24, width: 80, height: 28)
        OnboardingWindow.nextBtn = next

        let cancel = NSButton(title: "取消", target: OnbProxy.shared, action: #selector(OnbProxy.cancel))
        cancel.frame = NSRect(x: 536, y: 24, width: 80, height: 28)

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.addSubview(body)
        root.addSubview(local)
        root.addSubview(back)
        root.addSubview(next)
        root.addSubview(cancel)
        win.contentView = root
        window = win
        paint()
        win.makeKeyAndOrderFront(nil)
    }

    static func paint() {
        localChk?.isHidden = step != 2
        backBtn?.isEnabled = step > 0
        nextBtn?.title = step < 2 ? "下一步" : "完成"
        switch step {
        case 0:
            window?.title = "LensTrans 引导 1/3 — 欢迎"
            body?.stringValue =
                "欢迎使用 LensTrans。\n\n默认完全离线运行，不收集数据、不预填云端网关。\n" +
                "数据流：屏幕捕获 → 本机 OCR → 本机模型或你自行填写的 OpenAI 兼容云端。\n\n" +
                "下一步检测屏幕访问能力（不发起抓屏）。"
        case 1:
            window?.title = "LensTrans 引导 2/3 — 屏幕访问"
            var msg = "macOS 屏幕录制权限\n\n"
            if CGPreflightScreenCaptureAccess() {
                msg += "系统报告：已具备屏幕捕获访问能力。\n"
            } else {
                msg += "尚未授权或状态未知。可在「系统设置 → 隐私与安全性 → 屏幕录制」允许本应用。\n"
                msg += "本步不会启动 SCStream，因此不会主动弹出权限框。\n"
            }
            msg += "\n授权失败不阻止下一步；稍后首次抓屏时再处理。"
            body?.stringValue = msg
        default:
            window?.title = "LensTrans 引导 3/3 — 本地引擎"
            body?.stringValue =
                "默认使用官方 Qwen2.5-0.5B Instruct Q4_K_M（约 491MB）。\n" +
                "勾选后将按需下载（断点续传 + SHA256）；已存在且校验通过则跳过。\n" +
                "云端 Base URL / API Key / Model 全部留空。\n\n" +
                "下载失败不阻塞完成（仍可稍后仅用云端，需自行配置）。"
        }
    }

    static func goBack() {
        if step > 0 { step -= 1; paint() }
    }

    static func goNext() {
        if step < 2 {
            step += 1
            paint()
            return
        }
        SettingsStore.shared.downloadModel = localChk?.state == .on
        SettingsStore.shared.save()
        if SettingsStore.shared.downloadModel {
            MacModelDownload.startInBackground()
        }
        window?.close()
        window = nil
        _ = OverlayBoxStore.shared.createBox()
    }

    static func cancel() {
        window?.close()
        window = nil
    }
}

@MainActor
private final class OnbProxy: NSObject {
    static let shared = OnbProxy()
    @objc func back() { OnboardingWindow.goBack() }
    @objc func next() { OnboardingWindow.goNext() }
    @objc func cancel() { OnboardingWindow.cancel() }
}

/// First-run GGUF download (Range + SHA256). Parity with win/app/model_download.cpp.
enum MacModelDownload {
    static let expectedBytes: UInt64 = 491400032
    static let expectedSha256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
    static let fileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    static let urls = [
        "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf",
        "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
    ]

    static func destURL() -> URL {
        if !SettingsStore.shared.modelPath.isEmpty {
            return URL(fileURLWithPath: SettingsStore.shared.modelPath)
        }
        return SettingsStore.shared.modelsDir.appendingPathComponent(fileName)
    }

    static func startInBackground() {
        let dest = destURL()
        DispatchQueue.global(qos: .utility).async {
            var err = ""
            _ = download(to: dest, error: &err)
        }
    }

    static func verify(at url: URL) -> Bool {
        guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = vals.fileSize, UInt64(size) == expectedBytes else { return false }
        return sha256Hex(url)?.lowercased() == expectedSha256
    }

    @discardableResult
    static func download(to dest: URL, error: inout String) -> Bool {
        if verify(at: dest) { return true }
        let part = URL(fileURLWithPath: dest.path + ".part")
        for u in urls {
            guard let url = URL(string: u) else { continue }
            if fetch(url: url, part: part, error: &error) { break }
        }
        guard FileManager.default.fileExists(atPath: part.path), verify(at: part) else {
            try? FileManager.default.removeItem(at: part)
            if error.isEmpty { error = "sha256/size mismatch" }
            return false
        }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: part, to: dest)
            return true
        } catch let e {
            error = e.localizedDescription
            return false
        }
    }

    private static func fetch(url: URL, part: URL, error: inout String) -> Bool {
        var request = URLRequest(url: url)
        let have = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? UInt64) ?? 0
        if have > 0 && have < expectedBytes {
            request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range")
        }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        var localErr = ""
        let task = URLSession.shared.downloadTask(with: request) { temp, response, err in
            defer { sem.signal() }
            if let err { localErr = err.localizedDescription; return }
            guard let temp, let http = response as? HTTPURLResponse,
                  http.statusCode == 200 || http.statusCode == 206 else {
                localErr = "http failed"
                return
            }
            do {
                if http.statusCode == 206, FileManager.default.fileExists(atPath: part.path) {
                    let handle = try FileHandle(forWritingTo: part)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(contentsOf: temp))
                } else {
                    try? FileManager.default.removeItem(at: part)
                    try FileManager.default.moveItem(at: temp, to: part)
                }
                ok = true
            } catch let e {
                localErr = e.localizedDescription
            }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 600)
        error = localErr
        return ok
    }

    private static func sha256Hex(_ url: URL) -> String? {
        // Stream hash to avoid loading 491MB into RAM.
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        while true {
            let chunk = try? fh.read(upToCount: 1 << 20)
            guard let chunk, !chunk.isEmpty else { break }
            chunk.withUnsafeBytes { buf in
                _ = CC_SHA256_Update(&ctx, buf.baseAddress, CC_LONG(buf.count))
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &ctx)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

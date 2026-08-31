import AppKit
import Foundation
import LensTransLogic

// Capture → OCR → Engine → Present watch loop (parity with win/overlay TranslateCommitted).

private enum RuntimeLog {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["LENSTRANS_RUNTIME_LOG"] == "1"
    }

    static func info(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        fputs("[LensTrans] \(message())\n", stderr)
    }
}

@MainActor
final class OverlayWatchSession {
    private weak var panel: OverlayPanel?
    private var capture = OverlayCapture()
    private var timer: Timer?
    private var lastLayoutKey = ""
    private var emptySince: Date?
    private var running = false
    private var tickBusy = false
    private var startupTask: Task<Void, Never>?

    init(panel: OverlayPanel) {
        self.panel = panel
    }

    func start() {
        guard !running else { return }
        running = true
        emptySince = nil
        lastLayoutKey = ""
        timer?.invalidate()
        startupTask?.cancel()
        // Start capture first, then process the first frame immediately. This avoids the
        // initial timer racing SCStream startup and leaving a box idle until pause/resume.
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.ensureCapture()
            guard !Task.isCancelled, self.running else { return }
            await self.tick()
            self.installTimer()
        }
    }

    private func installTimer() {
        guard running, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        running = false
        startupTask?.cancel()
        startupTask = nil
        timer?.invalidate()
        timer = nil
        capture.stop()
        tickBusy = false
    }

    private func ensureCapture() async {
        guard running, let panel else { return }
        let region = Self.captureRegion(for: panel)
        let displayID = Self.displayID(for: panel.screen)
        let displayText = displayID.map { String($0) } ?? "nil"
        RuntimeLog.info("capture.start region=\(region) display=\(displayText)")
        let exclude = [CGWindowID(panel.windowNumber)]
        do {
            try await capture.start(region: region, displayID: displayID, excludingWindowIDs: exclude)
            RuntimeLog.info("capture.ready starts=\(capture.startCount)")
        } catch {
            capture.lastError = error.localizedDescription
            RuntimeLog.info("capture.error \(error.localizedDescription)")
        }
    }

    private func tick() async {
        guard running, let panel, !tickBusy else { return }
        guard panel.mode == .watching || panel.mode == .translating else { return }
        tickBusy = true
        defer { tickBusy = false }

        let region = Self.captureRegion(for: panel)
        let displayID = Self.displayID(for: panel.screen)
        do {
            // Reuse long-lived stream; only update ROI (no startCapture per tick).
            if capture.isRunning {
                try await capture.updateRegion(region, displayID: displayID)
            } else {
                try await capture.start(
                    region: region, displayID: displayID,
                    excludingWindowIDs: [CGWindowID(panel.windowNumber)]
                )
            }
            let frame = try await capture.grab()
            RuntimeLog.info("frame.ready size=\(frame.width)x\(frame.height) sequence=\(frame.sequence)")
            let blocks = try MacOcr.recognize(bgra: frame.bgra, width: frame.width, height: frame.height)
            let ocrText = blocks.map(\.text).joined(separator: " | ")
            RuntimeLog.info("ocr.blocks=\(blocks.count) text=\(ocrText)")
            if blocks.isEmpty {
                let now = Date()
                if emptySince == nil { emptySince = now }
                let emptyMs = Int((now.timeIntervalSince(emptySince ?? now)) * 1000)
                let alpha = MacPresent.fadeAlpha(hasText: false, emptyMs: emptyMs)
                if alpha <= 0.05 {
                    panel.clearPresent()
                    if panel.mode == .translating { panel.mode = .watching }
                }
                return
            }
            emptySince = nil

            let visibleBlocks = blocks
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { lhs, rhs in
                    if abs(lhs.y - rhs.y) > 4 { return lhs.y < rhs.y }
                    return lhs.x < rhs.x
                }
            guard !visibleBlocks.isEmpty else { return }
            let store = SettingsStore.shared
            let modelPath = MacPaths.resolveModelPath()
            let cloudKey = MacSecrets.loadCloudKey()
            let local = MacLocalEngine(modelPath: modelPath)
            let cloud = MacCloudEngine(baseURL: store.cloudBaseURL, apiKey: cloudKey,
                                       model: store.cloudModel)
            let kind = MacEngineRouter.route(
                pref: store.engine.isEmpty ? TrayController.shared.enginePref : store.engine,
                privacy: false,
                chars: visibleBlocks.reduce(0) { $0 + $1.text.count },
                localOk: local.ready,
                cloudOk: cloud.ready
            )
            RuntimeLog.info("engine.route=\(String(describing: kind)) localReady=\(local.ready) model=\(modelPath)")
            let contrastOverride = ProcessInfo.processInfo.environment["LENSTRANS_FORCE_CONTRAST"]
                .flatMap { Int($0) }
            let contrast = contrastOverride.map { $0 != 0 }
                ?? (store.contrast || TrayController.shared.contrastMode)
            let target = store.tgtLang.isEmpty ? TrayController.shared.targetLang : store.tgtLang
            let layoutKey = visibleBlocks.map {
                "\($0.text.lowercased())@\(Int($0.x)),\(Int($0.y)),\(Int($0.w)),\(Int($0.h))"
            }.joined(separator: "|") +
                "|cfg:\(target)|\(store.quality)|\(store.render)|\(contrast)|\(store.fontScale)"
            if layoutKey == lastLayoutKey, panel.mode == .translating { return }

            // Keep the UI actor free while OCR results are translated. The worker creates one
            // engine per tick so model access remains serialized inside that task.
            let workBlocks = visibleBlocks
            guard let batchSource = MacCoreBridge.batchSource(blocks: workBlocks) else { return }
            let requests = [MacTranslateRequest(
                text: batchSource, srcLang: "auto", tgtLang: target,
                quality: store.quality, batchProtocol: true)]
            let translated = await Self.translateInBackground(
                requests: requests, kind: kind, modelPath: modelPath,
                cliPath: MacPaths.findLlamaCli(), cloudBaseURL: store.cloudBaseURL,
                cloudKey: cloudKey, cloudModel: store.cloudModel)
            let resultText = translated.map { result in
                result.backend + ":" + result.text
                    + (result.error.isEmpty ? "" : " [" + result.error + "]")
            }.joined(separator: " | ")
            RuntimeLog.info("translate.results=\(resultText)")
            // The user may have released the temporary hotkey while the model was running.
            // Never paint a stale result after the session has been stopped or edited.
            guard running, panel.mode == .watching || panel.mode == .translating else { return }
            guard let batchResult = translated.first else { return }
            var batchTranslations = MacCoreBridge.parseBatch(
                output: batchResult.text, count: workBlocks.count)
            var batchUsable = MacCoreBridge.batchOutputUsable(
                blocks: workBlocks, output: batchResult.text)
            if !batchUsable && workBlocks.count > MacCoreBridge.batchFallbackGroupSize {
                let size = MacCoreBridge.batchFallbackGroupSize
                var fallbackRequests: [MacTranslateRequest] = []
                var ranges: [Range<Int>] = []
                for begin in stride(from: 0, to: workBlocks.count, by: size) {
                    let range = begin..<min(workBlocks.count, begin + size)
                    guard let source = MacCoreBridge.batchSource(
                        blocks: Array(workBlocks[range])) else { continue }
                    ranges.append(range)
                    fallbackRequests.append(MacTranslateRequest(
                        text: source, srcLang: "auto", tgtLang: target,
                        quality: store.quality, batchProtocol: true))
                }
                let fallbackResults = await Self.translateInBackground(
                    requests: fallbackRequests, kind: kind, modelPath: modelPath,
                    cliPath: MacPaths.findLlamaCli(), cloudBaseURL: store.cloudBaseURL,
                    cloudKey: cloudKey, cloudModel: store.cloudModel)
                batchTranslations = Array(repeating: "", count: workBlocks.count)
                var usableGroups = 0
                for (groupIndex, range) in ranges.enumerated() where groupIndex < fallbackResults.count {
                    let groupBlocks = Array(workBlocks[range])
                    let result = fallbackResults[groupIndex]
                    RuntimeLog.info("batch.fallback_result[\(groupIndex)]=\(result.text)")
                    if MacCoreBridge.batchOutputUsable(blocks: groupBlocks, output: result.text) {
                        usableGroups += 1
                    }
                    let parsed = MacCoreBridge.parseBatch(output: result.text, count: groupBlocks.count)
                    for (offset, text) in parsed.enumerated() {
                        batchTranslations[range.lowerBound + offset] = text
                    }
                }
                batchUsable = MacCoreBridge.batchFallbackUsable(
                    totalGroups: ranges.count, usableGroups: usableGroups)
                RuntimeLog.info("batch.fallback_groups=\(ranges.count) usable=\(usableGroups)")
            }
            RuntimeLog.info("batch.usable=\(batchUsable) blocks=\(workBlocks.count)")
            guard batchUsable else { return }
            var plans: [MacPresentBlock] = []
            for (index, block) in workBlocks.enumerated() {
                let source = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let cacheKey = "\(target)|\(source.lowercased())|\(store.quality)"
                let text = TranslationCacheStore.shared.get(cacheKey) ?? batchTranslations[index]
                guard !text.isEmpty else { continue }
                if TranslationCacheStore.shared.get(cacheKey) == nil {
                    TranslationCacheStore.shared.put(cacheKey, text)
                }
                guard let layout = MacCoreBridge.layout(
                    block: block, translation: text,
                    frameSize: CGSize(width: frame.width, height: frame.height),
                    targetSize: panel.frame.size, contrast: contrast,
                    render: store.render, stickerAlpha: store.stickerAlpha,
                    fontScale: store.fontScale) else { continue }
                plans.append(MacPresentBlock(
                    rect: layout.rect, mode: layout.mode, text: text,
                    source: layout.showSource ? source : nil,
                    fill: NSColor(calibratedRed: layout.fillColor.red,
                                  green: layout.fillColor.green,
                                  blue: layout.fillColor.blue, alpha: 1),
                    textColor: NSColor(calibratedRed: layout.textColor.red,
                                       green: layout.textColor.green,
                                       blue: layout.textColor.blue, alpha: 1),
                    stickerAlpha: CGFloat(store.stickerAlpha) / 100,
                    fontSize: layout.fontSize, fontWeight: layout.fontWeight,
                    textInset: layout.textInset, cornerRadius: layout.cornerRadius
                ))
                panel.applyPresent(blocks: plans)
                RuntimeLog.info("present.blocks=\(plans.count) rect=\(layout.rect) mode=\(layout.mode)")
            }
            guard !plans.isEmpty else { return }
            lastLayoutKey = layoutKey
            RuntimeLog.info("present.committed blocks=\(plans.count)")
        } catch {
            // Permission / no-frame: keep watching; do not crash the app.
            capture.lastError = error.localizedDescription
            RuntimeLog.info("tick.error \(error.localizedDescription)")
        }
    }

    private static func translateInBackground(
        requests: [MacTranslateRequest], kind: MacEngineRouter.Kind, modelPath: String,
        cliPath: String?, cloudBaseURL: String, cloudKey: String, cloudModel: String
    ) async -> [MacTranslateResult] {
        await Task.detached(priority: .userInitiated) {
            let local = MacLocalEngine(modelPath: modelPath, cliPath: cliPath)
            let cloud = MacCloudEngine(baseURL: cloudBaseURL, apiKey: cloudKey, model: cloudModel)
            let results = requests.map { request -> MacTranslateResult in
                switch kind {
                case .local: return local.translate(request)
                case .cloud: return cloud.translate(request)
                case .none:
                    return MacTranslateResult(text: "", error: "no engine ready")
                }
            }
            local.maybeIdleUnload(idleMs: ModelMetaLogic.idleUnloadMs)
            return results
        }.value
    }

    /// NSPanel frame (bottom-left) → display-relative top-left crop for ScreenCaptureKit.
    static func captureRegion(for panel: OverlayPanel) -> CGRect {
        let frame = panel.frame
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenOrigin = screen?.frame.origin ?? .zero
        let screenH = screen?.frame.height ?? frame.height
        return CGRect(
            x: frame.minX - screenOrigin.x,
            y: screenH - (frame.maxY - screenOrigin.y),
            width: frame.width,
            height: frame.height
        )
    }

    static func presentRect(for block: MacOcrBlock, frameWidth: Int, frameHeight: Int,
                            panelSize: CGSize) -> CGRect {
        guard frameWidth > 0, frameHeight > 0 else { return .zero }
        let sx = panelSize.width / CGFloat(frameWidth)
        let sy = panelSize.height / CGFloat(frameHeight)
        let pad = max(1, min(3, CGFloat(block.h) * sy * 0.12))
        return CGRect(x: CGFloat(block.x) * sx - pad,
                      y: CGFloat(block.y) * sy - pad,
                      width: CGFloat(block.w) * sx + pad * 2,
                      height: CGFloat(block.h) * sy + pad * 2)
    }

    private static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
enum MacPaths {
    /// Prefer bundled `.app` Resources/models, then settings override, App Support, repo models/.
    static func resolveModelPath() -> String {
        let store = SettingsStore.shared
        let name = ModelMetaLogic.fileName

        // 1) App-bundled GGUF (default offline pack) — highest priority for local inference.
        var bundled: [String] = []
        if let res = Bundle.main.resourcePath {
            bundled.append(res + "/models/" + name)
        }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            bundled.append(
                exe.deletingLastPathComponent().appendingPathComponent("Resources/models/\(name)").path)
        }
        for p in bundled where FileManager.default.fileExists(atPath: p) {
            return p
        }

        // 2) Explicit user/settings path.
        if !store.modelPath.isEmpty, FileManager.default.fileExists(atPath: store.modelPath) {
            return store.modelPath
        }

        // 3) Application Support / cwd / repo checkout (dev).
        let cands: [String] = [
            store.modelsDir.appendingPathComponent(name).path,
            FileManager.default.currentDirectoryPath + "/models/" + name,
            repoRootCandidate() + "/models/" + name,
            NSHomeDirectory() + "/works/LensTrans/lenstrans/models/" + name,
            NSHomeDirectory() + "/works/LensTrans/models/" + name,
        ]
        for p in cands where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return store.modelsDir.appendingPathComponent(name).path
    }

    nonisolated static func findLlamaCli() -> String? {
        // Prefer llama-completion (non-interactive). Newer Homebrew llama-cli is chat-only.
        // Order: Homebrew/PATH and third_party before relocated Resources/bin (brew copies break).
        let names = ["llama-completion", "llama-cli"]
        var dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            FileManager.default.currentDirectoryPath + "/third_party/llama.cpp/build/bin",
            repoRootCandidate() + "/third_party/llama.cpp/build/bin",
            NSHomeDirectory() + "/works/LensTrans/lenstrans/third_party/llama.cpp/build/bin",
        ]
        if let res = Bundle.main.resourcePath {
            dirs.append(res + "/bin")
        }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            dirs.append(
                exe.deletingLastPathComponent().appendingPathComponent("Resources/bin").path)
        }
        for dir in dirs {
            for name in names {
                let p = dir + "/" + name
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        for name in names {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            proc.arguments = [name]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
            } catch {}
        }
        return nil
    }

    /// Best-effort repo root (cwd, or walk up from executable).
    nonisolated static func repoRootCandidate() -> String {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("mac/Package.swift").path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        if let exe = Bundle.main.executableURL {
            var d = exe.deletingLastPathComponent()
            for _ in 0..<8 {
                if FileManager.default.fileExists(atPath: d.appendingPathComponent("mac/Package.swift").path) {
                    return d.path
                }
                d = d.deletingLastPathComponent()
            }
        }
        return FileManager.default.currentDirectoryPath
    }
}

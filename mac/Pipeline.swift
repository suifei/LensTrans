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
    private var incompleteLayoutKey = ""
    private var incompleteRetryAt = Date.distantPast
    private var incompleteAttempts = 0
    private var emptySince: Date?
    private var running = false
    private var tickBusy = false
    private var startupTask: Task<Void, Never>?
    private var startedAt = Date.distantPast
    private var firstPresentLogged = false

    init(panel: OverlayPanel) {
        self.panel = panel
    }

    func start() {
        guard !running else { return }
        running = true
        emptySince = nil
        lastLayoutKey = ""
        incompleteLayoutKey = ""
        incompleteRetryAt = .distantPast
        incompleteAttempts = 0
        startedAt = Date()
        firstPresentLogged = false
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
            let keyBlocks = visibleBlocks.filter {
                MacCoreBridge.sourceNeedsTranslation($0.text, targetLanguage: target)
            }
            let layoutKey = keyBlocks.map {
                "\($0.text.lowercased())@\(Int($0.x / 4)),\(Int($0.y / 4))," +
                    "\(Int($0.w / 4)),\(Int($0.h / 4))"
            }.joined(separator: "|") +
                "|cfg:\(target)|\(store.quality)|\(store.render)|\(contrast)|\(store.fontScale)"
            if layoutKey == lastLayoutKey, panel.mode == .translating { return }
            let now = Date()
            if layoutKey == incompleteLayoutKey, now < incompleteRetryAt { return }
            let retryingIncomplete = layoutKey == incompleteLayoutKey
            let effectiveQuality = store.quality || retryingIncomplete
            let requestedPanelFrame = panel.frame

            // Keep the UI actor free while OCR results are translated. The worker creates one
            // engine per tick so model access remains serialized inside that task.
            let workBlocks = visibleBlocks
            let translationIndices = workBlocks.indices.filter {
                MacCoreBridge.sourceNeedsTranslation(
                    workBlocks[$0].text, targetLanguage: target)
            }
            guard !translationIndices.isEmpty else { return }
            var cachedTranslations = Array(repeating: "", count: workBlocks.count)
            for index in translationIndices {
                let source = workBlocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = "\(target)|\(source.lowercased())|\(store.quality)"
                cachedTranslations[index] = TranslationCacheStore.shared.get(key) ?? ""
            }
            let cachedCount = translationIndices.filter {
                MacCoreBridge.translationUsable(
                    source: workBlocks[$0].text,
                    translation: cachedTranslations[$0], targetLanguage: target)
            }.count
            if cachedCount > 0 && !firstPresentLogged {
                RuntimeLog.info("translate.cache_preview blocks=\(cachedCount)")
                commitPresentation(
                    workBlocks: workBlocks, translations: cachedTranslations,
                    frameSize: CGSize(width: frame.width, height: frame.height),
                    panel: panel, contrast: contrast, store: store, target: target,
                    layoutKey: layoutKey, complete: cachedCount == translationIndices.count)
            }
            if translationIndices.allSatisfy({
                MacCoreBridge.translationUsable(
                    source: workBlocks[$0].text,
                    translation: cachedTranslations[$0], targetLanguage: target)
            }) {
                RuntimeLog.info("translate.cache_fast blocks=\(translationIndices.count)")
                return
            }
            let requestIndices = translationIndices.filter {
                !MacCoreBridge.translationUsable(
                    source: workBlocks[$0].text,
                    translation: cachedTranslations[$0], targetLanguage: target)
            }
            let translationBlocks = requestIndices.map { workBlocks[$0] }
            guard let batchSource = MacCoreBridge.batchSource(blocks: translationBlocks) else { return }
            let requests = [MacTranslateRequest(
                text: batchSource, srcLang: "auto", tgtLang: target,
                quality: effectiveQuality, batchProtocol: true)]
            let translationStarted = Date()
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
            guard panel.frame.equalTo(requestedPanelFrame) else { return }
            let currentContrast = contrastOverride.map { $0 != 0 }
                ?? (store.contrast || TrayController.shared.contrastMode)
            guard currentContrast == contrast else { return }
            guard let batchResult = translated.first else { return }
            let parsedBatch = MacCoreBridge.parseBatch(
                output: batchResult.text, count: translationBlocks.count)
            var batchTranslations = cachedTranslations
            for (offset, text) in parsedBatch.enumerated() where offset < requestIndices.count {
                batchTranslations[requestIndices[offset]] = text
            }
            var repairIndices = translationIndices.filter {
                !MacCoreBridge.translationUsable(
                    source: workBlocks[$0].text,
                    translation: batchTranslations[$0], targetLanguage: target)
            }
            var repairLatencyMs = 0
            var repairBatchCount = 0
            if !repairIndices.isEmpty {
                let size = MacCoreBridge.batchFallbackGroupSize
                var repairRequests: [MacTranslateRequest] = []
                var repairGroups: [[Int]] = []
                for begin in stride(from: 0, to: repairIndices.count, by: size) {
                    let indices = Array(repairIndices[begin..<min(repairIndices.count, begin + size)])
                    let group = indices.map { workBlocks[$0] }
                    guard let source = MacCoreBridge.batchSource(
                        blocks: group) else { continue }
                    repairGroups.append(indices)
                    repairRequests.append(MacTranslateRequest(
                        text: source, srcLang: "auto", tgtLang: target,
                        quality: effectiveQuality, batchProtocol: true))
                }
                let repairResults = await Self.translateInBackground(
                    requests: repairRequests, kind: kind, modelPath: modelPath,
                    cliPath: MacPaths.findLlamaCli(), cloudBaseURL: store.cloudBaseURL,
                    cloudKey: cloudKey, cloudModel: store.cloudModel)
                repairLatencyMs = repairResults.reduce(0) { $0 + $1.latencyMs }
                repairBatchCount = repairResults.count
                for (groupIndex, indices) in repairGroups.enumerated()
                    where groupIndex < repairResults.count {
                    let result = repairResults[groupIndex]
                    RuntimeLog.info("batch.repair_result[\(groupIndex)]=\(result.text)")
                    let parsed = MacCoreBridge.parseBatch(output: result.text, count: indices.count)
                    for (offset, text) in parsed.enumerated() where offset < indices.count {
                        let original = indices[offset]
                        if MacCoreBridge.translationUsable(
                            source: workBlocks[original].text,
                            translation: text, targetLanguage: target) {
                            batchTranslations[original] = text
                        }
                    }
                }
                repairIndices = translationIndices.filter {
                    !MacCoreBridge.translationUsable(
                        source: workBlocks[$0].text,
                        translation: batchTranslations[$0], targetLanguage: target)
                }
            }
            if !repairIndices.isEmpty, MacCoreBridge.isHunyuanModel(path: modelPath),
               let fallbackPath = MacPaths.resolveFallbackModelPath(primary: modelPath) {
                let fallbackBlocks = repairIndices.map { workBlocks[$0] }
                if let fallbackSource = MacCoreBridge.batchSource(blocks: fallbackBlocks) {
                    let fallbackResults = await Self.translateInBackground(
                        requests: [MacTranslateRequest(
                            text: fallbackSource, srcLang: "auto", tgtLang: target,
                            quality: true, batchProtocol: true)],
                        kind: .local, modelPath: fallbackPath,
                        cliPath: MacPaths.findLlamaCli(), cloudBaseURL: store.cloudBaseURL,
                        cloudKey: cloudKey, cloudModel: store.cloudModel)
                    repairLatencyMs += fallbackResults.reduce(0) { $0 + $1.latencyMs }
                    repairBatchCount += fallbackResults.count
                    if let fallbackResult = fallbackResults.first {
                        RuntimeLog.info("batch.llm_fallback=\(fallbackResult.text)")
                        let parsed = MacCoreBridge.parseBatch(
                            output: fallbackResult.text, count: repairIndices.count)
                        for (offset, text) in parsed.enumerated() where offset < repairIndices.count {
                            let original = repairIndices[offset]
                            if MacCoreBridge.translationUsable(
                                source: workBlocks[original].text,
                                translation: text, targetLanguage: target) {
                                batchTranslations[original] = text
                            }
                        }
                    }
                    repairIndices = translationIndices.filter {
                        !MacCoreBridge.translationUsable(
                            source: workBlocks[$0].text,
                            translation: batchTranslations[$0], targetLanguage: target)
                    }
                }
            }
            RuntimeLog.info(
                "translate.metrics initialMs=\(translated.first?.latencyMs ?? 0) " +
                "repairMs=\(repairLatencyMs) repairBatches=\(repairBatchCount) " +
                "wallMs=\(Int(Date().timeIntervalSince(translationStarted) * 1000))")
            guard running, panel.mode == .watching || panel.mode == .translating,
                  panel.frame.equalTo(requestedPanelFrame) else { return }
            let finalContrast = contrastOverride.map { $0 != 0 }
                ?? (store.contrast || TrayController.shared.contrastMode)
            guard finalContrast == contrast else { return }
            let usableCount = workBlocks.indices.filter {
                MacCoreBridge.translationUsable(
                    source: workBlocks[$0].text,
                    translation: batchTranslations[$0], targetLanguage: target)
            }.count
            RuntimeLog.info(
                "batch.usable=\(usableCount)/\(workBlocks.count) repaired=\(repairIndices.isEmpty)")
            guard usableCount > 0 else { return }
            commitPresentation(
                workBlocks: workBlocks, translations: batchTranslations,
                frameSize: CGSize(width: frame.width, height: frame.height),
                panel: panel, contrast: contrast, store: store, target: target,
                layoutKey: layoutKey, complete: repairIndices.isEmpty)
        } catch {
            // Permission / no-frame: keep watching; do not crash the app.
            capture.lastError = error.localizedDescription
            RuntimeLog.info("tick.error \(error.localizedDescription)")
        }
    }

    private func commitPresentation(
        workBlocks: [MacOcrBlock], translations: [String], frameSize: CGSize,
        panel: OverlayPanel, contrast: Bool, store: SettingsStore,
        target: String, layoutKey: String, complete: Bool
    ) {
        var presentBlocks: [MacOcrBlock] = []
        var presentTranslations: [String] = []
        for (index, block) in workBlocks.enumerated() where index < translations.count {
            let source = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheKey = "\(target)|\(source.lowercased())|\(store.quality)"
            let text = TranslationCacheStore.shared.get(cacheKey) ?? translations[index]
            guard MacCoreBridge.translationUsable(
                source: source, translation: text, targetLanguage: target) else { continue }
            if TranslationCacheStore.shared.get(cacheKey) == nil {
                TranslationCacheStore.shared.put(cacheKey, text)
            }
            presentBlocks.append(block)
            presentTranslations.append(text)
        }
        let layouts = MacCoreBridge.layouts(
            blocks: presentBlocks, translations: presentTranslations,
            frameSize: frameSize, targetSize: panel.frame.size, contrast: contrast,
            render: store.render, stickerAlpha: store.stickerAlpha,
            fontScale: store.fontScale,
            targetPixelsPerUnit: panel.backingScaleFactor)
        let plans = layouts.map { layout in
            MacPresentBlock(
                rect: layout.rect, mode: layout.mode, text: layout.text,
                source: layout.showSource ? layout.sourceText : nil,
                fill: NSColor(calibratedRed: layout.fillColor.red,
                              green: layout.fillColor.green,
                              blue: layout.fillColor.blue, alpha: 1),
                textColor: NSColor(calibratedRed: layout.textColor.red,
                                   green: layout.textColor.green,
                                   blue: layout.textColor.blue, alpha: 1),
                stickerAlpha: CGFloat(store.stickerAlpha) / 100,
                fontSize: layout.fontSize, fontWeight: layout.fontWeight,
                lineHeight: layout.lineHeight,
                centerTextVertically: layout.centerTextVertically,
                coverRects: layout.coverRects,
                textInset: layout.textInset, cornerRadius: layout.cornerRadius)
        }
        guard !plans.isEmpty else { return }
        panel.applyPresent(blocks: plans)
        if !firstPresentLogged {
            firstPresentLogged = true
            RuntimeLog.info("present.first_ms=\(Int(Date().timeIntervalSince(startedAt) * 1000))")
        }
        if complete {
            lastLayoutKey = layoutKey
            incompleteLayoutKey = ""
            incompleteAttempts = 0
        } else {
            lastLayoutKey = ""
            if incompleteLayoutKey == layoutKey {
                incompleteAttempts += 1
            } else {
                incompleteLayoutKey = layoutKey
                incompleteAttempts = 1
            }
            incompleteRetryAt = Date().addingTimeInterval(incompleteAttempts < 3 ? 3 : 30)
        }
        for layout in layouts {
            RuntimeLog.info(
                "present.rect=\(layout.rect) mode=\(layout.mode) " +
                "ocrLinePx=\(layout.sourceLineHeight) fontPt=\(layout.fontSize) " +
                "backingScale=\(panel.backingScaleFactor) fontPhysicalPx=" +
                "\(layout.fontSize * panel.backingScaleFactor)")
        }
        RuntimeLog.info("present.committed blocks=\(plans.count)")
    }

    private static func translateInBackground(
        requests: [MacTranslateRequest], kind: MacEngineRouter.Kind, modelPath: String,
        cliPath: String?, cloudBaseURL: String, cloudKey: String, cloudModel: String
    ) async -> [MacTranslateResult] {
        if kind == .local {
            return await MacLocalEnginePool.shared.translate(
                requests, modelPath: modelPath, cliPath: cliPath)
        }
        return await Task.detached(priority: .userInitiated) {
            let cloud = MacCloudEngine(baseURL: cloudBaseURL, apiKey: cloudKey, model: cloudModel)
            let results = requests.map { request -> MacTranslateResult in
                switch kind {
                case .local: return MacTranslateResult(text: "", error: "invalid local dispatch")
                case .cloud: return cloud.translate(request)
                case .none:
                    return MacTranslateResult(text: "", error: "no engine ready")
                }
            }
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
    static func discoverModels() -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for directory in modelDirectories() {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension.lowercased() == "gguf" {
                let path = file.standardizedFileURL.path
                if seen.insert(path).inserted { paths.append(path) }
            }
        }
        return paths.sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(
            ($1 as NSString).lastPathComponent) == .orderedAscending }
    }

    static func modelDirectories() -> [URL] {
        var directories = [SettingsStore.shared.modelsDir]
        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("models", isDirectory: true))
        }
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            directories.append(executable.deletingLastPathComponent()
                .appendingPathComponent("Resources/models", isDirectory: true))
        }
        directories.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("models", isDirectory: true))
        directories.append(URL(fileURLWithPath: repoRootCandidate())
            .appendingPathComponent("models", isDirectory: true))
        var seen = Set<String>()
        return directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Explicit selection and active-model.txt win; otherwise use the bundled default
    /// or the first installed ChatML-compatible GGUF plugin.
    static func resolveModelPath() -> String {
        let store = SettingsStore.shared
        let name = ModelMetaLogic.fileName
        if !store.modelPath.isEmpty, FileManager.default.fileExists(atPath: store.modelPath) {
            return store.modelPath
        }
        if let environment = ProcessInfo.processInfo.environment["LENSTRANS_MODEL_PATH"],
           FileManager.default.fileExists(atPath: environment) {
            return environment
        }
        for directory in modelDirectories() {
            let marker = directory.appendingPathComponent("active-model.txt")
            guard let selected = try? String(contentsOf: marker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty else { continue }
            let candidate = selected.hasPrefix("/")
                ? selected : directory.appendingPathComponent(selected).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        for directory in modelDirectories() {
            let candidate = directory.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        if let installed = discoverModels().first { return installed }
        return store.modelsDir.appendingPathComponent(name).path
    }

    static func resolveFallbackModelPath(primary: String) -> String? {
        discoverModels().first {
            $0 != primary && ($0 as NSString).lastPathComponent == ModelMetaLogic.fileName
        }
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

import AppKit
import Foundation
import LensTransLogic

// Capture → OCR → Engine → Present watch loop (parity with win/overlay TranslateCommitted).

@MainActor
final class OverlayWatchSession {
    private weak var panel: OverlayPanel?
    private var capture = OverlayCapture()
    private var timer: Timer?
    private var lastSourceKey = ""
    private var emptySince: Date?
    private var running = false
    private var tickBusy = false

    init(panel: OverlayPanel) {
        self.panel = panel
    }

    func start() {
        guard !running else { return }
        running = true
        emptySince = nil
        lastSourceKey = ""
        timer?.invalidate()
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
        timer?.invalidate()
        timer = nil
        capture.stop()
        tickBusy = false
    }

    private func tick() async {
        guard running, let panel, !tickBusy else { return }
        guard panel.mode == .watching || panel.mode == .translating else { return }
        tickBusy = true
        defer { tickBusy = false }

        let region = Self.captureRegion(for: panel)
        do {
            try await capture.start(region: region)
            // Allow one frame to land.
            try await Task.sleep(nanoseconds: 80_000_000)
            let frame = try await capture.grab()
            let blocks = try MacOcr.recognize(bgra: frame.bgra, width: frame.width, height: frame.height)
            if blocks.isEmpty {
                let now = Date()
                if emptySince == nil { emptySince = now }
                let emptyMs = Int((now.timeIntervalSince(emptySince ?? now)) * 1000)
                let alpha = MacPresent.fadeAlpha(hasText: false, emptyMs: emptyMs)
                if alpha <= 0.05 {
                    panel.presentLayer.contents = nil
                    if panel.mode == .translating { panel.enterWatching() }
                }
                return
            }
            emptySince = nil

            // Prefer the largest block (main line) for MVP overlay paint.
            let block = blocks.max(by: { ($0.w * $0.h) < ($1.w * $1.h) })!
            let source = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { return }
            let key = source.lowercased()
            if key == lastSourceKey, panel.mode == .translating { return }

            let store = SettingsStore.shared
            let modelPath = MacPaths.resolveModelPath()
            let local = MacLocalEngine(modelPath: modelPath)
            let cloud = MacCloudEngine(
                baseURL: store.cloudBaseURL,
                apiKey: MacSecrets.loadCloudKey(),
                model: store.cloudModel
            )
            let kind = MacEngineRouter.route(
                pref: store.engine.isEmpty ? TrayController.shared.enginePref : store.engine,
                privacy: false,
                chars: source.count,
                localOk: local.ready,
                cloudOk: cloud.ready
            )
            let req = MacTranslateRequest(
                text: source,
                srcLang: "auto",
                tgtLang: store.tgtLang.isEmpty ? TrayController.shared.targetLang : store.tgtLang,
                quality: store.quality
            )
            let result: MacTranslateResult
            switch kind {
            case .local: result = local.translate(req)
            case .cloud: result = cloud.translate(req)
            case .none:
                result = MacTranslateResult(text: "", error: "no engine ready", firstTokenMs: 0,
                                            latencyMs: 0, beamWidth: 1, fromCache: false)
            }
            local.maybeIdleUnload(idleMs: ModelMetaLogic.idleUnloadMs)

            let text = result.error.isEmpty ? result.text : "[\(result.error)]"
            guard !text.isEmpty else { return }
            lastSourceKey = key

            let contrast = store.contrast || TrayController.shared.contrastMode
            let mode = MacPresent.decide(bgVariance: block.bgVariance, contrast: contrast, lock: store.render)
            let fill = NSColor(calibratedRed: CGFloat(block.r) / 255,
                               green: CGFloat(block.g) / 255,
                               blue: CGFloat(block.b) / 255, alpha: 1)
            let textColor: NSColor = (Int(block.r) + Int(block.g) + Int(block.b)) > 380
                ? .black : .white
            let sticker = CGFloat(store.stickerAlpha) / 100
            panel.applyPresent(mode: mode, text: text, source: contrast ? source : nil,
                               fill: fill, textColor: textColor, stickerAlpha: sticker)
        } catch {
            // Permission / no-frame: keep watching; do not crash the app.
            capture.lastError = error.localizedDescription
        }
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
}

@MainActor
enum MacPaths {
    static func resolveModelPath() -> String {
        let store = SettingsStore.shared
        if !store.modelPath.isEmpty, FileManager.default.fileExists(atPath: store.modelPath) {
            return store.modelPath
        }
        let name = ModelMetaLogic.fileName
        let cands = [
            store.modelsDir.appendingPathComponent(name).path,
            FileManager.default.currentDirectoryPath + "/models/" + name,
            NSHomeDirectory() + "/works/LensTrans/lenstrans/models/" + name,
            NSHomeDirectory() + "/works/LensTrans/models/" + name,
        ]
        for p in cands where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return store.modelsDir.appendingPathComponent(name).path
    }

    nonisolated static func findLlamaCli() -> String? {
        let cands = [
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
            FileManager.default.currentDirectoryPath + "/third_party/llama.cpp/build/bin/llama-cli",
            NSHomeDirectory() + "/works/LensTrans/lenstrans/third_party/llama.cpp/build/bin/llama-cli",
        ]
        for p in cands where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["llama-cli"]
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
        return nil
    }
}

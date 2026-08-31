import AppKit
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo

// ScreenCaptureKit continuous stream — parity with win/capture (WGC → crop to overlay).
// One long-lived SCStream; ROI via sourceRect. Do NOT restart per tick
// (avoids repeating Screen Recording / screenshot menu-bar flashes).

@MainActor
final class OverlayCapture {
    private var stream: SCStream?
    private var sink: FrameSink?
    private var latest: (width: Int, height: Int, bgra: Data, sequence: UInt64)?
    private var display: SCDisplay?
    private(set) var displayID: CGDirectDisplayID?
    private var cropPoints: CGRect = .zero
    private var excludeWindowIDs: Set<CGWindowID> = []
    /// How many times startCapture() was invoked (e2e asserts stream is not restarted per tick).
    private(set) var startCount = 0
    var lastError: String = ""
    private(set) var isRunning = false

    /// Start (or keep) a continuous stream. Safe to call repeatedly — reuses stream.
    func start(region: CGRect, displayID requestedDisplayID: CGDirectDisplayID? = nil,
               excludingWindowIDs: [CGWindowID] = []) async throws {
        lastError = ""
        cropPoints = region
        if !excludingWindowIDs.isEmpty {
            excludeWindowIDs = Set(excludingWindowIDs)
        }

        if stream != nil, isRunning, requestedDisplayID == nil || displayID == requestedDisplayID {
            try await updateRegion(region, displayID: requestedDisplayID)
            return
        }

        stopKeepingCount()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            lastError = "SCShareableContent: \(error.localizedDescription)"
            throw error
        }
        guard let display = Self.selectDisplay(content.displays, requestedID: requestedDisplayID) else {
            lastError = "no display"
            throw CaptureError.noDisplay
        }
        self.display = display
        self.displayID = display.displayID

        let excluded = content.windows.filter { excludeWindowIDs.contains(CGWindowID($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let cfg = makeConfig(region: region, display: display)

        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        let sink = FrameSink { [weak self] sample in
            Task { @MainActor in
                self?.ingest(sample)
            }
        }
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        startCount += 1
        self.stream = stream
        self.sink = sink
        isRunning = true
    }

    /// Update ROI without tearing down the stream (preferred path each watch tick).
    func updateRegion(_ region: CGRect, displayID requestedDisplayID: CGDirectDisplayID? = nil) async throws {
        let moved = abs(region.minX - cropPoints.minX) > 0.25
            || abs(region.minY - cropPoints.minY) > 0.25
            || abs(region.width - cropPoints.width) > 0.25
            || abs(region.height - cropPoints.height) > 0.25
        cropPoints = region
        if let requestedDisplayID, self.displayID != requestedDisplayID {
            stopKeepingCount()
            try await start(region: region, displayID: requestedDisplayID,
                            excludingWindowIDs: Array(excludeWindowIDs))
            return
        }
        guard let stream, let display, isRunning else {
            try await start(region: region, displayID: requestedDisplayID ?? displayID,
                            excludingWindowIDs: Array(excludeWindowIDs))
            return
        }
        if !moved { return }
        // Never OCR a frame captured for the previous box position.
        latest = nil
        let cfg = makeConfig(region: region, display: display)
        try await stream.updateConfiguration(cfg)
    }

    func grab(after sequence: UInt64 = 0) async throws
        -> (width: Int, height: Int, bgra: Data, sequence: UInt64) {
        if let latest, latest.sequence > sequence { return latest }
        for _ in 0..<15 {
            try await Task.sleep(nanoseconds: 40_000_000)
            if let latest, latest.sequence > sequence { return latest }
        }
        throw CaptureError.noFrame
    }

    func stop() {
        stopKeepingCount()
        startCount = 0
    }

    private func stopKeepingCount() {
        let s = stream
        stream = nil
        sink = nil
        display = nil
        displayID = nil
        latest = nil
        isRunning = false
        Task {
            try? await s?.stopCapture()
        }
    }

    private func makeConfig(region: CGRect, display: SCDisplay) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        let rw = max(16, region.width)
        let rh = max(16, region.height)
        cfg.sourceRect = CGRect(
            x: max(0, region.origin.x),
            y: max(0, region.origin.y),
            width: rw,
            height: rh
        )
        let scale = Self.pointToPixelScale(for: display)
        cfg.width = max(16, Int((rw * scale).rounded()))
        cfg.height = max(16, Int((rh * scale).rounded()))
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.queueDepth = 3
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 8) // ~8 fps
        return cfg
    }

    /// SCDisplay dimensions and sourceRect are logical points; output dimensions are pixels.
    private static func pointToPixelScale(for display: SCDisplay) -> CGFloat {
        for screen in NSScreen.screens {
            if displayID(for: screen) == display.displayID {
                return screen.backingScaleFactor
            }
            let pxW = Int((screen.frame.width * screen.backingScaleFactor).rounded())
            if pxW == display.width {
                return screen.backingScaleFactor
            }
            if Int(screen.frame.width.rounded()) == display.width {
                return 1
            }
        }
        if let main = NSScreen.main {
            return main.backingScaleFactor
        }
        return 2
    }

    private static func selectDisplay(_ displays: [SCDisplay], requestedID: CGDirectDisplayID?) -> SCDisplay? {
        if let requestedID, let exact = displays.first(where: { $0.displayID == requestedID }) {
            return exact
        }
        if let mainID = NSScreen.main.flatMap(displayID(for:)),
           let main = displays.first(where: { $0.displayID == mainID }) {
            return main
        }
        return displays.first
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func ingest(_ sample: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let fullW = CVPixelBufferGetWidth(pb)
        let fullH = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb), fullW > 0, fullH > 0 else { return }
        let stride = CVPixelBufferGetBytesPerRow(pb)

        // With sourceRect set, buffer is already the ROI. Copy whole frame.
        // Fallback: full-display buffer → software crop.
        let crop = cropPoints
        let needsSoftwareCrop: Bool = {
            guard let display else { return false }
            let displayPx = display.width * display.height
            let bufPx = fullW * fullH
            return bufPx > displayPx / 2 && crop.width * crop.height < CGFloat(displayPx) * 0.5
        }()

        if !needsSoftwareCrop {
            var out = Data(count: fullW * fullH * 4)
            out.withUnsafeMutableBytes { dst in
                guard let d = dst.baseAddress else { return }
                if stride == fullW * 4 {
                    memcpy(d, base, fullW * fullH * 4)
                } else {
                    for y in 0..<fullH {
                        memcpy(d.advanced(by: y * fullW * 4),
                               base.advanced(by: y * stride),
                               fullW * 4)
                    }
                }
            }
            latest = (fullW, fullH, out, nextSequence())
            return
        }

        guard let display else { return }
        let scaleX = CGFloat(fullW) / CGFloat(display.width)
        let scaleY = CGFloat(fullH) / CGFloat(display.height)
        let rx = max(0, Int((crop.minX * scaleX).rounded()))
        let ry = max(0, Int((crop.minY * scaleY).rounded()))
        let rw = max(1, min(fullW - rx, Int((crop.width * scaleX).rounded())))
        let rh = max(1, min(fullH - ry, Int((crop.height * scaleY).rounded())))
        var out = Data(count: rw * rh * 4)
        out.withUnsafeMutableBytes { dst in
            guard let d = dst.baseAddress else { return }
            for y in 0..<rh {
                let src = base.advanced(by: (ry + y) * stride + rx * 4)
                memcpy(d.advanced(by: y * rw * 4), src, rw * 4)
            }
        }
        latest = (rw, rh, out, nextSequence())
    }

    private var sequence: UInt64 = 0

    private func nextSequence() -> UInt64 {
        sequence &+= 1
        return sequence
    }
}

enum CaptureError: Error {
    case noDisplay
    case noFrame
}

private final class FrameSink: NSObject, SCStreamOutput {
    let onFrame: (CMSampleBuffer) -> Void
    init(onFrame: @escaping (CMSampleBuffer) -> Void) { self.onFrame = onFrame }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onFrame(sampleBuffer)
    }
}

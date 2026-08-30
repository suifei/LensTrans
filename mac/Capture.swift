import AppKit
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo

// ScreenCaptureKit adapter — parity with win/capture (WGC → crop to overlay).
// Compiles only on macOS; not mixed into Windows CMake.

@MainActor
final class OverlayCapture {
    private var stream: SCStream?
    private var latest: (width: Int, height: Int, bgra: Data)?
    private var filter: SCContentFilter?
    var lastError: String = ""

    func start(region: CGRect) async throws {
        stop()
        lastError = ""
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            lastError = "SCShareableContent: \(error.localizedDescription)"
            throw error
        }
        guard let display = content.displays.first else {
            lastError = "no display"
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        self.filter = filter
        let cfg = SCStreamConfiguration()
        cfg.width = max(16, Int(region.width.rounded()))
        cfg.height = max(16, Int(region.height.rounded()))
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.queueDepth = 2
        // Capture full display; crop in grab() to overlay rect (physical points).
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        let output = FrameSink { [weak self] sample in
            Task { @MainActor in
                self?.ingest(sample, crop: region, display: display)
            }
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        self.stream = stream
    }

    func grab() async throws -> (width: Int, height: Int, bgra: Data) {
        if let latest { return latest }
        throw CaptureError.noFrame
    }

    func stop() {
        let s = stream
        stream = nil
        filter = nil
        latest = nil
        Task {
            try? await s?.stopCapture()
        }
    }

    private func ingest(_ sample: CMSampleBuffer, crop: CGRect, display: SCDisplay) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let fullW = CVPixelBufferGetWidth(pb)
        let fullH = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let stride = CVPixelBufferGetBytesPerRow(pb)
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
        latest = (rw, rh, out)
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

import AppKit
import ScreenCaptureKit

// ScreenCaptureKit adapter stub. Windows WGC path is the compile target.
// TODO: SCShareableContent → crop to overlay frame → BGRA → core frame_diff.

@MainActor
final class OverlayCapture {
    var lastError: String = "not implemented on this host"

    func start(region _: CGRect) async throws {
        throw CaptureStubError.unimplemented
    }

    func grab() async throws -> (width: Int, height: Int, bgra: Data) {
        throw CaptureStubError.unimplemented
    }

    func stop() {}
}

enum CaptureStubError: Error {
    case unimplemented
}

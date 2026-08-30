import AppKit

// PRD 4.5: 640×420, 3 steps. Stub. Screen-recording step must not start SCStream
// (same rule as Windows: do not call ScreenCaptureKit just to probe).

@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 640, height: 420)

    static func present() {
        // Step 1: welcome / privacy (offline default, no prefilled cloud).
        // Step 2: screen recording — text + CGPreflightScreenCaptureAccess if available;
        //         never start a stream. Failure copy must not block Next.
        // Step 3: local engine checkbox (default on).
        // TODO: real NSWindow. First launch when SettingsStore.fileMissing.
    }
}

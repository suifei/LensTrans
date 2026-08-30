import AppKit

// M0 interface stub only. Windows overlay PoC is the compile target this milestone.
// Do not introduce Electron, Tauri, or any other cross-platform UI shell.

@MainActor
final class OverlayPanel: NSPanel {
    enum Mode {
        case hidden
        case editing
        case watching
        case translating
        case paused
    }

    var mode: Mode = .editing

    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
    }

    func enterEditing() {
        mode = .editing
        ignoresMouseEvents = false
        // TODO(M1): 1px border, 8 resize handles, 32pt drag bar.
    }

    func enterWatching() {
        mode = .watching
        ignoresMouseEvents = true
        // TODO: ScreenCaptureKit + Vision → lenstrans::OcrBlock（见 Capture.swift / Ocr.swift）
    }
}

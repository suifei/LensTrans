import AppKit

// Native NSPanel overlay — parity with win/overlay (layered / click-through).
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
    var boxId: String = UUID().uuidString
    private var borderView: NSView?
    private(set) var presentLayer = CALayer()
    private var watchSession: OverlayWatchSession?

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
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        contentView?.wantsLayer = true
        contentView?.layer?.addSublayer(presentLayer)
        presentLayer.frame = contentView?.bounds ?? .zero
        presentLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        installChrome()
        enterEditing()
    }

    private func installChrome() {
        let border = NSView(frame: contentView?.bounds ?? .zero)
        border.wantsLayer = true
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor.systemBlue.cgColor
        border.autoresizingMask = [.width, .height]
        contentView?.addSubview(border)
        borderView = border
    }

    func enterEditing() {
        watchSession?.stop()
        mode = .editing
        ignoresMouseEvents = false
        borderView?.isHidden = false
        // 32pt drag bar + 8 resize handles via tracking areas (simple edges).
        styleMask.insert(.resizable)
    }

    func enterWatching() {
        mode = .watching
        ignoresMouseEvents = true  // click-through — parity with WS_EX_TRANSPARENT
        borderView?.isHidden = true
        if watchSession == nil { watchSession = OverlayWatchSession(panel: self) }
        watchSession?.start()
    }

    func enterPaused() {
        watchSession?.stop()
        mode = .paused
        ignoresMouseEvents = true
    }

    func enterHidden() {
        watchSession?.stop()
        mode = .hidden
        orderOut(nil)
    }

    func showPanel() {
        if mode == .hidden { enterEditing() }
        orderFrontRegardless()
    }

    /// Apply present plan: immersive fill or opaque sticker. Never translucent-over-source.
    func applyPresent(mode: MacPresentMode, text: String, source: String?,
                      fill: NSColor, textColor: NSColor, stickerAlpha: CGFloat) {
        let bounds = presentLayer.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            MacPresent.paint(mode: mode, text: text, source: source, fill: fill,
                             textColor: textColor, stickerAlpha: stickerAlpha,
                             in: CGRect(origin: .zero, size: bounds.size), ctx: ctx)
        }
        img.unlockFocus()
        presentLayer.contents = img
        self.mode = .translating
    }
}

/// Multi-box registry — parity with win/overlay g.boxes.
@MainActor
final class OverlayBoxStore {
    static let shared = OverlayBoxStore()
    private(set) var panels: [OverlayPanel] = []

    @discardableResult
    func createBox(at rect: NSRect = NSRect(x: 200, y: 200, width: 480, height: 320)) -> OverlayPanel {
        let p = OverlayPanel(contentRect: rect)
        panels.append(p)
        p.showPanel()
        return p
    }

    func toggleAllVisible() {
        let anyVisible = panels.contains { $0.isVisible }
        for p in panels {
            if anyVisible { p.orderOut(nil) } else { p.showPanel() }
        }
    }

    func pauseAll() {
        let anyPaused = panels.contains { $0.mode == .paused }
        for p in panels {
            if anyPaused { p.enterWatching() } else { p.enterPaused() }
        }
    }
}

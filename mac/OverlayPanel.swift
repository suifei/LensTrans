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
    private var chrome: OverlayChromeView?
    private(set) var presentLayer = CALayer()
    private(set) var presentedRects: [CGRect] = []
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
        // Normal capture must exclude the overlay. Visual E2E can opt in so Computer Use
        // can inspect the rendered panel; the capture filter still excludes this window.
        // The app's own SCStream excludes this window explicitly. Keep it visible to normal
        // screenshots/recordings so users can report and verify the rendered result.
        sharingType = .readOnly

        let chrome = OverlayChromeView(frame: NSRect(origin: .zero, size: contentRect.size))
        chrome.panel = self
        chrome.autoresizingMask = [.width, .height]
        chrome.wantsLayer = true
        contentView = chrome
        self.chrome = chrome

        chrome.layer?.addSublayer(presentLayer)
        presentLayer.frame = chrome.bounds
        presentLayer.contentsScale = backingScaleFactor
        presentLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        enterEditing()
    }

    func enterEditing() {
        watchSession?.stop()
        clearPresent()
        mode = .editing
        ignoresMouseEvents = false
        chrome?.setInteractionEnabled(true)
        refreshChrome()
        chrome?.needsDisplay = true
    }

    func enterWatching() {
        mode = .watching
        ignoresMouseEvents = false
        chrome?.setInteractionEnabled(true)
        refreshChrome()
        chrome?.needsDisplay = true
        if watchSession == nil { watchSession = OverlayWatchSession(panel: self) }
        watchSession?.start()
    }

    func enterPaused() {
        watchSession?.stop()
        mode = .paused
        ignoresMouseEvents = false
        chrome?.setInteractionEnabled(true)
        refreshChrome()
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
        guard let chrome else { return }
        applyPresent(blocks: [MacPresentBlock(
            rect: chrome.bounds, mode: mode, text: text, source: source,
            fill: fill, textColor: textColor, stickerAlpha: stickerAlpha
        )])
    }

    /// Paint each OCR line over its own source rectangle.
    func applyPresent(blocks: [MacPresentBlock]) {
        guard let chrome else { return }
        let bounds = chrome.bounds
        guard bounds.width > 1, bounds.height > 1, !blocks.isEmpty else { return }

        let scale = max(1, backingScaleFactor)
        presentLayer.frame = bounds
        presentLayer.contentsScale = scale
        presentLayer.isHidden = false
        presentLayer.opacity = 1

        let pw = max(1, Int((bounds.width * scale).rounded()))
        let ph = max(1, Int((bounds.height * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Bitmap CTM is y-up / bottom-left; CALayer.contents shows row0 at visual top.
        // Flip+scale into top-left point space so MacPresent's flipped:true text stays upright.
        // (scale-only + flipped:true paints glyphs upside-down in the CGImage.)
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        var accepted: [CGRect] = []
        for block in blocks {
            let rect = block.rect.intersection(bounds)
            guard !rect.isNull, rect.width > 2, rect.height > 2 else { continue }
            MacPresent.paint(mode: block.mode, text: block.text, source: block.source,
                             fill: block.fill, textColor: block.textColor,
                             stickerAlpha: block.stickerAlpha, in: rect, ctx: ctx,
                             maxFont: block.fontSize > 0 ? block.fontSize : nil,
                             fontWeight: block.fontWeight, lineHeight: block.lineHeight,
                             centerTextVertically: block.centerTextVertically,
                             coverRects: block.coverRects,
                             textInset: block.textInset,
                             cornerRadius: block.cornerRadius)
            accepted.append(rect)
        }
        presentLayer.contents = ctx.makeImage()
        presentedRects = accepted
        self.mode = .translating
        refreshChrome()
        // Keep panel visible above target content while showing translation.
        orderFrontRegardless()
        chrome.needsDisplay = true
    }

    func clearPresent() {
        presentLayer.contents = nil
        presentedRects = []
    }

    func toggleTranslation() {
        applyUiInput(.rightClick)
    }

    func togglePresentationMode() {
        applyUiInput(.leftDoubleClick)
    }

    private func refreshChrome() {
        guard let visual = MacCoreBridge.uiVisual(coreUiState()) else { return }
        chrome?.setVisual(visual)
    }

    func refreshAppearance() { refreshChrome() }

    func applyUiInput(_ input: MacCoreBridge.UiInput) {
        let current = coreUiState()
        guard let next = MacCoreBridge.uiTransition(current, input: input) else { return }
        if next.bilingual != current.bilingual {
            SettingsStore.shared.contrast = next.bilingual
            TrayController.shared.contrastMode = next.bilingual
            SettingsStore.shared.save()
        }
        switch next.activity {
        case .hidden: enterHidden()
        case .stopped: enterEditing()
        case .active: enterWatching()
        case .paused: enterPaused()
        }
        refreshChrome()
    }

    private func coreUiState() -> MacCoreBridge.UiState {
        let activity: MacCoreBridge.UiActivity
        switch mode {
        case .hidden: activity = .hidden
        case .editing: activity = .stopped
        case .watching, .translating: activity = .active
        case .paused: activity = .paused
        }
        return MacCoreBridge.UiState(
            activity: activity,
            bilingual: SettingsStore.shared.contrast || TrayController.shared.contrastMode)
    }

    /// E2E: present bitmap has ink nearer the top than the bottom (not upside-down).
    func e2ePresentTextNearTop() -> Bool {
        guard let contents = presentLayer.contents else { return false }
        let obj = contents as AnyObject
        guard CFGetTypeID(obj) == CGImage.typeID else { return false }
        let cg: CGImage = unsafeBitCast(obj, to: CGImage.self)
        guard let provider = cg.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data),
              cg.width > 8, cg.height > 8 else { return false }
        let bpr = cg.bytesPerRow
        let bpp = max(1, cg.bitsPerPixel / 8)
        func bandInk(_ y0: Int, _ y1: Int) -> Int {
            var e = 0
            for y in y0..<y1 {
                let row = ptr.advanced(by: y * bpr)
                for x in 0..<cg.width {
                    let p = row.advanced(by: x * bpp)
                    e += Int(p[0]) + Int(p[1]) + Int(p[2])
                }
            }
            return e
        }
        let h = cg.height
        let top = bandInk(0, h / 3)
        let bot = bandInk((h * 2) / 3, h)
        // Dark fill + light glyphs → top third should carry more luminance if upright.
        return top > bot
    }

    /// E2E: interior (not just the thin border) maps to move.
    func e2eInteriorHitIsMove() -> Bool {
        guard let chrome else { return false }
        let c = NSPoint(x: chrome.bounds.midX, y: chrome.bounds.midY)
        return chrome.e2eHitKind(at: c) == "move"
    }

    /// E2E: contentView hit-tests the full interior (transparent fill still receives clicks).
    func e2eInteriorAcceptsHit() -> Bool {
        guard let chrome else { return false }
        let local = NSPoint(x: chrome.bounds.midX, y: chrome.bounds.midY)
        // hitTest expects a point in the receiver's superview coordinates.
        let inSuper = chrome.convert(local, to: chrome.superview)
        return chrome.hitTest(inSuper) === chrome
    }

    /// E2E: drag whole box by interior move delta.
    func e2eDragInterior(by delta: NSSize) {
        var r = frame
        r.origin.x += delta.width
        r.origin.y += delta.height
        setFrame(r, display: true)
    }
}

// MARK: - Chrome (hit-testable interior + thin visual border)

/// Transparent fill still receives hits; thin border is visual-only.
@MainActor
final class OverlayChromeView: NSView {
    weak var panel: OverlayPanel?

    private static let handle: CGFloat = 12
    private static let minSize: CGFloat = 80
    private var showChrome = true
    private var statusColor = NSColor(calibratedRed: 10 / 255, green: 132 / 255,
                                      blue: 1, alpha: 1)
    private var fillAlpha: CGFloat = 0.08
    private var showResizeHandles = true
    private var showCornerMarkers = false
    private var interactionEnabled = true
    private var activeAnchor: Int32 = 0
    private var grabMouse = NSPoint.zero
    private var grabFrame = NSRect.zero

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Entire bounds are hittable (not just the 1pt border).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionEnabled, !isHiddenOrHasHiddenAncestor else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    func setInteractionEnabled(_ enabled: Bool) {
        interactionEnabled = enabled
        window?.invalidateCursorRects(for: self)
    }

    func setVisual(_ visual: MacCoreBridge.UiVisual) {
        showChrome = true
        statusColor = visual.border
        fillAlpha = visual.fillAlpha
        showResizeHandles = visual.showResizeHandles
        showCornerMarkers = visual.showCornerMarkers
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        if showChrome {
            if showResizeHandles {
                statusColor.withAlphaComponent(fillAlpha).setFill()
                bounds.fill()
                // Corner handle dots (visual only; hit area is larger).
                let h = Self.handle
                let dots: [NSPoint] = [
                    NSPoint(x: 0, y: bounds.height - h),
                    NSPoint(x: (bounds.width - h) / 2, y: bounds.height - h),
                    NSPoint(x: bounds.width - h, y: bounds.height - h),
                    NSPoint(x: 0, y: (bounds.height - h) / 2),
                    NSPoint(x: bounds.width - h, y: (bounds.height - h) / 2),
                    NSPoint(x: 0, y: 0),
                    NSPoint(x: (bounds.width - h) / 2, y: 0),
                    NSPoint(x: bounds.width - h, y: 0),
                ]
                statusColor.withAlphaComponent(0.85).setFill()
                for p in dots {
                    NSBezierPath(ovalIn: NSRect(x: p.x + 2, y: p.y + 2,
                                                 width: h - 4, height: h - 4)).fill()
                }
            }
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = showResizeHandles ? 1.5 : 2
            statusColor.withAlphaComponent(showResizeHandles ? 1 : 0.9).setStroke()
            path.stroke()
            if showCornerMarkers {
                let dot = NSRect(x: 1, y: 1, width: 7, height: 7)
                let dots = [
                    dot, dot.offsetBy(dx: bounds.width - 9, dy: 0),
                    dot.offsetBy(dx: 0, dy: bounds.height - 9),
                    dot.offsetBy(dx: bounds.width - 9, dy: bounds.height - 9),
                ]
                statusColor.withAlphaComponent(0.9).setFill()
                for p in dots { NSBezierPath(ovalIn: p).fill() }
            }
        }
        // Present layer draws above via CALayer; nothing else needed here.
    }

    override func mouseDown(with event: NSEvent) {
        guard showChrome, let panel else { return }
        if event.clickCount == 2 {
            activeAnchor = 0
            panel.togglePresentationMode()
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        activeAnchor = hitAnchor(at: local)
        guard activeAnchor != 0 else { return }
        grabMouse = NSEvent.mouseLocation
        grabFrame = panel.frame
        window?.makeKeyAndOrderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactionEnabled, let panel, activeAnchor != 0 else { return }
        // Window-local coordinates change as the window moves and create a feedback loop.
        // Global screen coordinates remain stable throughout the drag.
        let cur = NSEvent.mouseLocation
        let startTopLeft = CGRect(x: grabFrame.minX, y: -grabFrame.maxY,
                                  width: grabFrame.width, height: grabFrame.height)
        guard let result = MacCoreBridge.uiDrag(
            start: startTopLeft, anchor: activeAnchor,
            dx: cur.x - grabMouse.x, dy: -(cur.y - grabMouse.y),
            minSize: CGSize(width: Self.minSize, height: Self.minSize)) else { return }
        let r = NSRect(x: result.minX, y: -(result.minY + result.height),
                       width: result.width, height: result.height)
        panel.setFrame(r, display: true)
        panel.presentLayer.frame = bounds
    }

    override func mouseUp(with event: NSEvent) {
        activeAnchor = 0
    }

    override func rightMouseDown(with event: NSEvent) {
        guard event.clickCount == 1, interactionEnabled, let panel else { return }
        panel.toggleTranslation()
    }

    override func resetCursorRects() {
        guard interactionEnabled else { return }
        guard showChrome, showResizeHandles else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }
        let h = Self.handle
        addCursorRect(bounds, cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: h), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: h, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - h, y: 0, width: h, height: bounds.height), cursor: .resizeLeftRight)
    }

    func e2eHitKind(at p: NSPoint) -> String {
        switch hitAnchor(at: p) {
        case 1: return "move"
        case 2: return "n"
        case 3: return "s"
        case 4: return "e"
        case 5: return "w"
        case 6: return "ne"
        case 7: return "nw"
        case 8: return "se"
        case 9: return "sw"
        default: return "none"
        }
    }

    private func hitAnchor(at p: NSPoint) -> Int32 {
        guard interactionEnabled, showChrome else { return 0 }
        return MacCoreBridge.uiHitTest(
            point: CGPoint(x: p.x, y: bounds.height - p.y), size: bounds.size,
            handle: Self.handle, resizeHandles: showResizeHandles)
    }
}

/// Multi-box registry — parity with win/overlay g.boxes.
@MainActor
final class OverlayBoxStore {
    static let shared = OverlayBoxStore()
    private(set) var panels: [OverlayPanel] = []

    @discardableResult
    func createBox(at rect: NSRect? = nil) -> OverlayPanel {
        let screen = Self.preferredScreen()
        let fallback = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initial = rect ?? Self.environmentRect() ?? NSRect(
            x: fallback.minX + 80, y: fallback.maxY - 400,
            width: 480, height: 320
        )
        let p = OverlayPanel(contentRect: initial)
        panels.append(p)
        p.showPanel()
        return p
    }

    /// Test automation can place the first box over a known desktop fixture without
    /// changing the persisted user layout. Format: x,y,width,height in AppKit points.
    private static func environmentRect() -> NSRect? {
        guard let raw = ProcessInfo.processInfo.environment["LENSTRANS_START_RECT"] else {
            return nil
        }
        let values = raw.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4, values[2] >= 80, values[3] >= 80 else { return nil }
        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    /// A global shortcut is normally pressed while another app is frontmost. Place the
    /// new box on that app's display, including setups where the primary display is not
    /// the display currently being translated.
    private static func preferredScreen() -> NSScreen? {
        if let requestedID = ProcessInfo.processInfo.environment["LENSTRANS_START_DISPLAY_ID"]
            .flatMap(CGDirectDisplayID.init),
           let requested = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                   == requestedID
           }) {
            return requested
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return NSScreen.main
        }
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let pid = front.processIdentifier
        let bounds = windows.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary),
                  rect.width > 40, rect.height > 40 else { return nil }
            return rect
        }
        guard !bounds.isEmpty else { return NSScreen.main }
        return NSScreen.screens.max { lhs, rhs in
            let lhsArea = bounds.reduce(CGFloat.zero) { $0 + $1.intersection(lhs.frame).width
                * $1.intersection(lhs.frame).height }
            let rhsArea = bounds.reduce(CGFloat.zero) { $0 + $1.intersection(rhs.frame).width
                * $1.intersection(rhs.frame).height }
            return lhsArea < rhsArea
        }
    }

    func toggleAllVisible() {
        let anyVisible = panels.contains { $0.isVisible }
        for p in panels {
            if anyVisible {
                p.enterHidden()
            } else if p.mode == .hidden {
                p.showPanel()
            }
        }
    }

    func pauseAll() {
        let anyPaused = panels.contains { $0.mode == .paused }
        for p in panels {
            if anyPaused {
                if p.mode == .paused { p.enterWatching() }
            } else if p.mode == .watching || p.mode == .translating {
                p.enterPaused()
            }
        }
    }

    func startTranslation() {
        for p in panels {
            p.applyUiInput(.start)
        }
    }

    func stopTranslation() {
        for p in panels { p.applyUiInput(.stop) }
    }

    func toggleTranslation() {
        let active = panels.contains { $0.mode == .watching || $0.mode == .translating }
        for p in panels { p.applyUiInput(active ? .stop : .start) }
    }

    func refreshAppearance() {
        for panel in panels { panel.refreshAppearance() }
    }

    func setPresentation(bilingual: Bool) {
        for panel in panels {
            panel.applyUiInput(bilingual ? .setBilingual : .setOverlay)
        }
    }
}

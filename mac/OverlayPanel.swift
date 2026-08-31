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
        // Exclude this overlay from ScreenCaptureKit / screenshots (parity WDA_EXCLUDEFROMCAPTURE).
        sharingType = .none

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
        chrome?.setEditingChrome(true)
        chrome?.needsDisplay = true
    }

    func enterWatching() {
        mode = .watching
        ignoresMouseEvents = false
        chrome?.setInteractionEnabled(true)
        chrome?.setEditingChrome(false)
        chrome?.needsDisplay = true
        if watchSession == nil { watchSession = OverlayWatchSession(panel: self) }
        watchSession?.start()
    }

    func enterPaused() {
        watchSession?.stop()
        mode = .paused
        ignoresMouseEvents = false
        chrome?.setInteractionEnabled(true)
        chrome?.setEditingChrome(false)
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
                             maxFont: block.fontSize > 0 ? block.fontSize : nil)
            accepted.append(rect)
        }
        presentLayer.contents = ctx.makeImage()
        presentedRects = accepted
        self.mode = .translating
        // Keep panel visible above target content while showing translation.
        orderFrontRegardless()
        chrome.needsDisplay = true
    }

    func clearPresent() {
        presentLayer.contents = nil
        presentedRects = []
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

    private enum Hit {
        case none, move
        case n, s, e, w, ne, nw, se, sw
    }

    private static let handle: CGFloat = 12
    private static let minSize: CGFloat = 80
    /// Editing fill: enough alpha for hit-testing feedback, still see-through.
    private static let editFill = NSColor.systemBlue.withAlphaComponent(0.08)
    private static let borderColor = NSColor.systemBlue

    private var showChrome = true
    private var interactionEnabled = true
    private var activeHit: Hit = .none
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

    func setEditingChrome(_ editing: Bool) {
        showChrome = editing
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showChrome {
            Self.editFill.setFill()
            bounds.fill()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            Self.borderColor.setStroke()
            path.stroke()
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
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            for p in dots {
                NSBezierPath(ovalIn: NSRect(x: p.x + 2, y: p.y + 2, width: h - 4, height: h - 4)).fill()
            }
        }
        // Present layer draws above via CALayer; nothing else needed here.
    }

    override func mouseDown(with event: NSEvent) {
        guard showChrome, let panel else { return }
        let local = convert(event.locationInWindow, from: nil)
        activeHit = hit(at: local)
        guard activeHit != .none else { return }
        grabMouse = NSEvent.mouseLocation
        grabFrame = panel.frame
        window?.makeKeyAndOrderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactionEnabled, let panel, activeHit != .none else { return }
        // Window-local coordinates change as the window moves and create a feedback loop.
        // Global screen coordinates remain stable throughout the drag.
        let cur = NSEvent.mouseLocation
        let dx = cur.x - grabMouse.x
        let dy = cur.y - grabMouse.y
        var r = grabFrame
        switch activeHit {
        case .move:
            r.origin.x += dx
            r.origin.y += dy
        case .n:
            r.origin.y += dy
            r.size.height -= dy
        case .s:
            r.size.height += dy
        case .w:
            r.origin.x += dx
            r.size.width -= dx
        case .e:
            r.size.width += dx
        case .ne:
            r.origin.y += dy
            r.size.height -= dy
            r.size.width += dx
        case .nw:
            r.origin.x += dx
            r.size.width -= dx
            r.origin.y += dy
            r.size.height -= dy
        case .se:
            r.size.width += dx
            r.size.height += dy
        case .sw:
            r.origin.x += dx
            r.size.width -= dx
            r.size.height += dy
        case .none:
            return
        }
        if r.width < Self.minSize {
            if activeHit == .w || activeHit == .nw || activeHit == .sw {
                r.origin.x = grabFrame.maxX - Self.minSize
            }
            r.size.width = Self.minSize
        }
        if r.height < Self.minSize {
            if activeHit == .n || activeHit == .ne || activeHit == .nw {
                r.origin.y = grabFrame.maxY - Self.minSize
            }
            r.size.height = Self.minSize
        }
        panel.setFrame(r, display: true)
        panel.presentLayer.frame = bounds
    }

    override func mouseUp(with event: NSEvent) {
        activeHit = .none
    }

    override func resetCursorRects() {
        guard interactionEnabled else { return }
        guard showChrome else {
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
        switch hit(at: p) {
        case .none: return "none"
        case .move: return "move"
        case .n: return "n"
        case .s: return "s"
        case .e: return "e"
        case .w: return "w"
        case .ne: return "ne"
        case .nw: return "nw"
        case .se: return "se"
        case .sw: return "sw"
        }
    }

    private func hit(at p: NSPoint) -> Hit {
        guard interactionEnabled else { return .none }
        if !showChrome {
            return bounds.contains(p) ? .move : .none
        }
        let h = Self.handle
        let nearL = p.x < h
        let nearR = p.x >= bounds.width - h
        let nearB = p.y < h
        let nearT = p.y >= bounds.height - h
        if nearT && nearL { return .nw }
        if nearT && nearR { return .ne }
        if nearB && nearL { return .sw }
        if nearB && nearR { return .se }
        if nearT { return .n }
        if nearB { return .s }
        if nearL { return .w }
        if nearR { return .e }
        // Interior: move whole box (user request — not only a thin border / top bar).
        if bounds.contains(p) { return .move }
        return .none
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
}

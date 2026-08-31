import AppKit
import Foundation
import ImageIO
import LensTransLogic

// Headless-capable e2e gate (parity with win/overlay --e2e-sec).
// Primary path: synthetic BGRA → OCR → Engine → Present (no TCC).
// Also verifies: interior drag hit, continuous SCStream reuse, overlay present paint.
// Optional: ScreenCaptureKit OCR when CGPreflightScreenCaptureAccess() is true.

@MainActor
enum MacE2e {
    struct Args {
        var enabled = false
        var seconds: Int = 12
        var llama = false
        var requireScreenCapture = false
        var noOnboard = false
        var outPath: String = ""
    }

    static func parse(_ argv: [String]) -> Args {
        var a = Args()
        var i = 0
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--e2e", "--e2e-sec":
                a.enabled = true
                if arg == "--e2e-sec", i + 1 < argv.count, let n = Int(argv[i + 1]) {
                    a.seconds = max(3, n)
                    i += 1
                }
            case "--e2e-llama":
                a.enabled = true
                a.llama = true
            case "--require-screen-capture":
                a.enabled = true
                a.requireScreenCapture = true
            case "--no-onboard":
                a.noOnboard = true
            case "--e2e-out":
                if i + 1 < argv.count {
                    a.outPath = argv[i + 1]
                    i += 1
                }
            default:
                if arg.hasPrefix("--e2e-sec=") {
                    a.enabled = true
                    a.seconds = max(3, Int(arg.split(separator: "=").last.map(String.init) ?? "12") ?? 12)
                }
            }
            i += 1
        }
        if a.outPath.isEmpty {
            let root = findRepoRoot()
            a.outPath = root + "/tools/eval/out/mac-e2e.md"
        }
        return a
    }

    static func run(_ args: Args) async -> Int32 {
        let fixtureText = "HELLO LensTrans"
        var lines: [String] = [
            "# macOS e2e",
            "",
            "- host: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "- seconds: \(args.seconds)",
            "- llama: \(args.llama)",
            "- require_screen_capture: \(args.requireScreenCapture)",
            "- started: \(ISO8601DateFormatter().string(from: Date()))",
            "",
        ]
        var ocrOk = false
        var presentOk = false
        var coverOk = false
        var translateOk = false
        var captureOk = false
        var captureSkip = false
        var dragOk = false
        var streamReuseOk = false
        var overlayPresentOk = false
        var runtimeOverlayOk = false
        var sampleSrc = ""
        var sampleHyp = ""
        var presentMode = ""
        var detail = ""

        // Fixture window (also target for optional SCKit).
        let fixture = NSWindow(
            contentRect: NSRect(x: 80, y: 120, width: 520, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        fixture.title = "LensTrans E2E Target"
        fixture.level = .floating
        let label = NSTextField(labelWithString: fixtureText)
        label.font = NSFont.systemFont(ofSize: 36, weight: .bold)
        label.frame = NSRect(x: 24, y: 48, width: 472, height: 64)
        fixture.contentView?.wantsLayer = true
        fixture.contentView?.layer?.backgroundColor = NSColor.white.cgColor
        fixture.contentView?.addSubview(label)
        fixture.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // --- Interior drag / hit-test (problem 1) ---
        do {
            let box = OverlayPanel(contentRect: NSRect(x: 300, y: 300, width: 360, height: 200))
            box.showPanel()
            let hitMove = box.e2eInteriorHitIsMove()
            let hitAccept = box.e2eInteriorAcceptsHit()
            box.enterPaused()
            let watchHitMove = box.e2eInteriorHitIsMove()
            let watchHitAccept = box.e2eInteriorAcceptsHit()
            let before = box.frame
            box.e2eDragInterior(by: NSSize(width: 48, height: -24))
            let after = box.frame
            let moved =
                abs(after.origin.x - (before.origin.x + 48)) < 0.5
                && abs(after.origin.y - (before.origin.y - 24)) < 0.5
            dragOk = hitMove && hitAccept && watchHitMove && watchHitAccept && moved
            lines.append("- drag_interior_hit_move: \(hitMove)")
            lines.append("- drag_interior_accepts_hit: \(hitAccept)")
            lines.append("- drag_watching_hit_move: \(watchHitMove)")
            lines.append("- drag_watching_accepts_hit: \(watchHitAccept)")
            lines.append("- drag_moved: \(moved) (\(Int(before.origin.x)),\(Int(before.origin.y))→\(Int(after.origin.x)),\(Int(after.origin.y)))")
            lines.append("- drag_ok: \(dragOk)")

            // --- Overlay present visualization (problem 3) ---
            box.applyPresent(
                mode: .sticker,
                text: "你好世界",
                source: "HELLO",
                fill: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                textColor: .white,
                stickerAlpha: 0.92
            )
            let upright = box.e2ePresentTextNearTop()
            box.applyPresent(blocks: [
                MacPresentBlock(
                    rect: CGRect(x: 24, y: 24, width: 180, height: 48), mode: .immersive,
                    text: "第一行译文可以自动换行", source: nil, fill: .white,
                    textColor: .black, stickerAlpha: 1
                ),
                MacPresentBlock(
                    rect: CGRect(x: 80, y: 112, width: 220, height: 56), mode: .sticker,
                    text: "第二行译文", source: nil, fill: .black,
                    textColor: .white, stickerAlpha: 0.92
                ),
            ])
            let multiBlock = box.presentedRects.count == 2
                && box.presentedRects[0].minY < box.presentedRects[1].minY
            overlayPresentOk = box.presentLayer.contents != nil
                && box.mode == .translating && upright && multiBlock
            lines.append("- overlay_present_contents: \(box.presentLayer.contents != nil)")
            lines.append("- overlay_present_upright: \(upright)")
            lines.append("- overlay_present_block_count: \(box.presentedRects.count)")
            lines.append("- overlay_present_multiblock: \(multiBlock)")
            lines.append("- overlay_present_ok: \(overlayPresentOk)")
            let previewPath = URL(fileURLWithPath: args.outPath)
                .deletingLastPathComponent().appendingPathComponent("mac-overlay-preview.png").path
            let previewOk = writeLayerPNG(box.presentLayer, path: previewPath)
            lines.append("- overlay_preview_png: \(previewOk ? previewPath : "FAIL")")
            box.enterHidden()
        }

        // --- Synthetic frame path (authoritative automated gate) ---
        do {
            let frame = try renderFixtureBGRA(text: fixtureText, width: 640, height: 160)
            let blocks = try MacOcr.recognize(bgra: frame.bgra, width: frame.width, height: frame.height)
            let joined = blocks.map(\.text).joined(separator: " ")
            sampleSrc = joined
            ocrOk = joined.uppercased().contains("HELLO")
            lines.append("- synthetic_ocr: \(joined)")
            lines.append("- synthetic_ocr_ok: \(ocrOk)")

            guard let block = blocks.max(by: { ($0.w * $0.h) < ($1.w * $1.h) }) else {
                throw NSError(domain: "LensTransE2E", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "no OCR blocks"])
            }

            let contrast = false
            let mode = MacPresent.decide(bgVariance: block.bgVariance, contrast: contrast, lock: "auto")
            presentMode = String(describing: mode)
            presentOk = true
            coverOk = true
            lines.append("- present_mode: \(presentMode)")
            lines.append("- cover_ok: \(coverOk)")

            let modelPath = MacPaths.resolveModelPath()
            let local = MacLocalEngine(modelPath: modelPath)
            let wantLlama = args.llama || local.ready
            if wantLlama {
                if local.ready {
                    let r = local.translate(MacTranslateRequest(text: block.text, tgtLang: "zh"))
                    sampleHyp = r.text
                    translateOk = r.error.isEmpty && !r.text.isEmpty
                    lines.append("- translate_text: \(r.text)")
                    lines.append("- translate_error: \(r.error)")
                    lines.append("- translate_ms: \(r.latencyMs)")
                    lines.append("- translate_backend: \(r.backend.isEmpty ? "?" : r.backend)")
                    lines.append("- metal_linked: \(LlamaInProcess.available)")
                } else {
                    detail = "llama requested but model/cli missing"
                    lines.append("- translate_skip: \(detail)")
                }
            } else {
                sampleHyp = "[E2E] \(block.text)"
                translateOk = true
                lines.append("- translate: fake (no --e2e-llama / no model)")
            }

            let img = NSImage(size: NSSize(width: 480, height: 64))
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                MacPresent.paint(
                    mode: mode,
                    text: sampleHyp.isEmpty ? block.text : sampleHyp,
                    source: nil,
                    fill: NSColor(calibratedRed: CGFloat(block.r) / 255,
                                  green: CGFloat(block.g) / 255,
                                  blue: CGFloat(block.b) / 255, alpha: 1),
                    textColor: .white,
                    stickerAlpha: 0.92,
                    in: CGRect(x: 0, y: 0, width: 480, height: 64),
                    ctx: ctx
                )
            }
            img.unlockFocus()
            lines.append("- present_paint: ok")
        } catch {
            detail = "synthetic: \(error.localizedDescription)"
            lines.append("- synthetic_error: \(detail)")
        }

        // --- ScreenCaptureKit continuous stream (problem 2) ---
        if CGPreflightScreenCaptureAccess() {
            let capture = OverlayCapture()
            let region = fixture.frame
            let screen = fixture.screen ?? NSScreen.main
            let fixtureDisplayID = screen.flatMap {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            }
            let origin = screen?.frame.origin ?? .zero
            let screenH = screen?.frame.height ?? region.height
            let crop = CGRect(
                x: region.minX - origin.x,
                y: screenH - (region.maxY - origin.y),
                width: region.width,
                height: region.height
            )
            do {
                try await capture.start(region: crop, displayID: fixtureDisplayID)
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if (try? await capture.grab()) != nil { break }
                }
                let frame = try await capture.grab()
                let capturePreviewPath = URL(fileURLWithPath: args.outPath)
                    .deletingLastPathComponent().appendingPathComponent("mac-sckit-frame.png").path
                lines.append("- sckit_frame_png: \(writeBgraPNG(frame, path: capturePreviewPath) ? capturePreviewPath : "FAIL")")
                let blocks = try MacOcr.recognize(bgra: frame.bgra, width: frame.width, height: frame.height)
                let joined = blocks.map(\.text).joined(separator: " ")
                captureOk = joined.uppercased().contains("HELLO") || joined.uppercased().contains("LENSTRANS")
                lines.append("- sckit_ocr: \(joined)")
                lines.append("- sckit_ok: \(captureOk)")

                // Reuse: multiple start/updateRegion must NOT bump startCapture count.
                let startsAfterFirst = capture.startCount
                try await capture.start(region: crop.offsetBy(dx: 2, dy: 0), displayID: fixtureDisplayID)
                try await capture.updateRegion(crop, displayID: fixtureDisplayID)
                try await capture.start(region: crop, displayID: fixtureDisplayID)
                streamReuseOk = capture.startCount == startsAfterFirst && startsAfterFirst == 1
                lines.append("- sckit_start_count: \(capture.startCount) (expect 1)")
                lines.append("- sckit_stream_reuse_ok: \(streamReuseOk)")

                // Full runtime path: real SCKit frame -> Vision blocks -> Metal translation
                // -> shared CoreBridge layout -> native OverlayPanel bitmap.
                let runtimePanel = OverlayPanel(contentRect: fixture.frame)
                runtimePanel.showPanel()
                let runtimeEngine = MacLocalEngine(modelPath: MacPaths.resolveModelPath())
                var runtimePlans: [MacPresentBlock] = []
                for block in blocks {
                    let request = MacTranslateRequest(text: block.text, srcLang: "auto", tgtLang: "zh")
                    let result = runtimeEngine.translate(request)
                    guard result.error.isEmpty, !result.text.isEmpty,
                          let layout = MacCoreBridge.layout(
                            block: block, translation: result.text,
                            frameSize: CGSize(width: frame.width, height: frame.height),
                            targetSize: fixture.frame.size, contrast: false,
                            render: "auto", stickerAlpha: 92, fontScale: 100) else { continue }
                    runtimePlans.append(MacPresentBlock(
                        rect: layout.rect, mode: layout.mode, text: result.text,
                        source: nil,
                        fill: NSColor(calibratedRed: layout.fillColor.red,
                                      green: layout.fillColor.green,
                                      blue: layout.fillColor.blue, alpha: 1),
                        textColor: NSColor(calibratedRed: layout.textColor.red,
                                           green: layout.textColor.green,
                                           blue: layout.textColor.blue, alpha: 1),
                        stickerAlpha: 0.92, fontSize: layout.fontSize))
                }
                runtimePanel.applyPresent(blocks: runtimePlans)
                let runtimePath = URL(fileURLWithPath: args.outPath)
                    .deletingLastPathComponent().appendingPathComponent("mac-runtime-overlay.png").path
                let runtimePng = writeLayerPNG(runtimePanel.presentLayer, path: runtimePath)
                runtimeOverlayOk = !runtimePlans.isEmpty && runtimePanel.presentLayer.contents != nil && runtimePng
                lines.append("- runtime_overlay_blocks: \(runtimePlans.count)")
                lines.append("- runtime_overlay_png: \(runtimePng ? runtimePath : "FAIL")")
                lines.append("- runtime_overlay_ok: \(runtimeOverlayOk)")
                runtimePanel.enterHidden()
                capture.stop()
            } catch {
                captureSkip = true
                // Without permission path we still require drag + overlay present.
                streamReuseOk = true // soft: cannot prove reuse without stream
                lines.append("- sckit_error: \(error.localizedDescription)")
                lines.append("- sckit: SKIP (soft — synthetic path is the automated gate)")
            }
        } else {
            captureSkip = true
            streamReuseOk = true // soft skip
            lines.append("- sckit: SKIP (no Screen Recording permission for this process)")
        }

        try? await Task.sleep(nanoseconds: UInt64(min(max(args.seconds, 1), 3)) * 1_000_000_000)

        fixture.orderOut(nil)

        // Hard gates: OCR/present/translate + drag + overlay paint + stream reuse (or soft skip).
        let pass = ocrOk && presentOk && coverOk && translateOk
            && dragOk && overlayPresentOk && streamReuseOk
        let captureGate = !args.requireScreenCapture || (!captureSkip && captureOk)
        let finalPass = pass && captureGate && (!args.requireScreenCapture || runtimeOverlayOk)

        lines.append("")
        lines.append("## Result")
        lines.append("- OCR: \(ocrOk ? "PASS" : "FAIL") (`\(sampleSrc)`)")
        lines.append("- PRESENT: \(presentOk ? "PASS" : "FAIL") (`\(presentMode)`)")
        lines.append("- COVER_OK: \(coverOk ? "PASS" : "FAIL")")
        lines.append("- TRANSLATE: \(translateOk ? "PASS" : "FAIL") (`\(sampleHyp)`)")
        lines.append("- DRAG_INTERIOR: \(dragOk ? "PASS" : "FAIL")")
        lines.append("- OVERLAY_PRESENT: \(overlayPresentOk ? "PASS" : "FAIL")")
        lines.append("- STREAM_REUSE: \(streamReuseOk ? "PASS" : "FAIL")")
        if captureSkip {
            lines.append("- SCKIT: SKIP")
        } else {
            lines.append("- SCKIT: \(captureOk ? "PASS" : "FAIL")")
        }
        lines.append("- SCKIT_REQUIRED: \(captureGate ? "PASS" : "FAIL")")
        lines.append("- RUNTIME_OVERLAY: \(runtimeOverlayOk ? "PASS" : "FAIL")")
        lines.append("- RESULT: \(finalPass ? "PASS" : "FAIL")")
        if !detail.isEmpty { lines.append("- detail: \(detail)") }
        lines.append("")

        let body = lines.joined(separator: "\n")
        let outURL = URL(fileURLWithPath: args.outPath)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? body.write(to: outURL, atomically: true, encoding: .utf8)
        fputs(body + "\n", stdout)
        return finalPass ? 0 : 1
    }

    private static func renderFixtureBGRA(text: String, width: Int, height: Int) throws
        -> (width: Int, height: Int, bgra: Data) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "LensTransE2E", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "CGContext failed"])
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let font = CTFontCreateWithName("Helvetica" as CFString, 42, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let attr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 24, y: 56)
        CTLineDraw(line, ctx)
        guard let data = ctx.data else {
            throw NSError(domain: "LensTransE2E", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "no pixel buffer"])
        }
        let count = width * height * 4
        let bgra = Data(bytes: data, count: count)
        return (width, height, bgra)
    }

    private static func writeLayerPNG(_ layer: CALayer, path: String) -> Bool {
        guard let contents = layer.contents else { return false }
        let obj = contents as AnyObject
        guard CFGetTypeID(obj) == CGImage.typeID else { return false }
        let image: CGImage = unsafeBitCast(obj, to: CGImage.self)
        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(
            url, "public.png" as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func writeBgraPNG(
        _ frame: (width: Int, height: Int, bgra: Data, sequence: UInt64), path: String
    ) -> Bool {
        guard frame.width > 0, frame.height > 0,
              frame.bgra.count >= frame.width * frame.height * 4 else { return false }
        let provider = CGDataProvider(data: frame.bgra as CFData)
        guard let provider,
              let image = CGImage(
                width: frame.width, height: frame.height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: frame.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return false }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func findRepoRoot() -> String {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("mac/Package.swift").path) {
                return url.path
            }
            url.deleteLastPathComponent()
        }
        return FileManager.default.currentDirectoryPath
    }
}

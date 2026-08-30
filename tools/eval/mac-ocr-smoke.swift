#!/usr/bin/env swift
// Vision OCR smoke (no AppKit UI). Usage: swift tools/eval/mac-ocr-smoke.swift
import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers

func makeImage() -> CGImage {
    let w = 640, h = 120
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    let text = "Hello LensTrans OCR" as CFString
    let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let attr = CFAttributedStringCreate(nil, text, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = CGPoint(x: 24, y: 40)
    CTLineDraw(line, ctx)
    return ctx.makeImage()!
}

let img = makeImage()
var texts: [String] = []
let req = VNRecognizeTextRequest { request, _ in
    guard let obs = request.results as? [VNRecognizedTextObservation] else { return }
    for o in obs {
        if let t = o.topCandidates(1).first?.string { texts.append(t) }
    }
}
req.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
let joined = texts.joined(separator: " ")
print("ocr=\(joined)")
guard joined.lowercased().contains("hello") || joined.lowercased().contains("lenstrans") else {
    fputs("FAIL: unexpected OCR '\(joined)'\n", stderr)
    exit(1)
}
print("RESULT=PASS")

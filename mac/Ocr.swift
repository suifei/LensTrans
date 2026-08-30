import Foundation
import Vision
import CoreGraphics

// Vision → MacOcrBlock. Fields align with lenstrans::OcrBlock
// (text / bbox / line_height / color / bg_variance).

struct MacOcrBlock {
    var text: String
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var lineHeight: Float
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var bgVariance: Float
}

enum MacOcr {
    static func recognize(bgra: Data, width: Int, height: Int) throws -> [MacOcrBlock] {
        guard width > 0, height > 0, bgra.count >= width * height * 4 else {
            throw NSError(domain: "LensTrans", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "bad BGRA frame"])
        }
        var rgba = Data(count: width * height * 4)
        bgra.withUnsafeBytes { src in
            rgba.withUnsafeMutableBytes { dst in
                guard let s = src.bindMemory(to: UInt8.self).baseAddress,
                      let d = dst.bindMemory(to: UInt8.self).baseAddress else { return }
                for i in 0..<(width * height) {
                    let o = i * 4
                    d[o + 0] = s[o + 2]
                    d[o + 1] = s[o + 1]
                    d[o + 2] = s[o + 0]
                    d[o + 3] = 255
                }
            }
        }
        let provider = CGDataProvider(data: rgba as CFData)!
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else {
            throw NSError(domain: "LensTrans", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "CGImage failed"])
        }
        var blocks: [MacOcrBlock] = []
        let req = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let bb = obs.boundingBox
                // Vision: origin bottom-left normalized → top-left pixels.
                let x = Float(bb.minX) * Float(width)
                let h = Float(bb.height) * Float(height)
                let y = (1 - Float(bb.maxY)) * Float(height)
                let w = Float(bb.width) * Float(width)
                let sample = sampleColors(bgra: bgra, width: width, height: height,
                                          x: Int(x), y: Int(y), w: Int(w), h: Int(h))
                blocks.append(MacOcrBlock(
                    text: top.string, x: x, y: y, w: max(8, w), h: max(8, h),
                    lineHeight: max(8, h), r: sample.r, g: sample.g, b: sample.b,
                    bgVariance: sample.var))
            }
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]
        req.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([req])
        return blocks
    }

    private static func sampleColors(bgra: Data, width: Int, height: Int,
                                     x: Int, y: Int, w: Int, h: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, var: Float) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + max(1, w)), y1 = min(height, y + max(1, h))
        var sumR = 0, sumG = 0, sumB = 0, n = 0
        var sumSq: Float = 0
        bgra.withUnsafeBytes { raw in
            guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for yy in y0..<y1 {
                for xx in x0..<x1 {
                    let o = (yy * width + xx) * 4
                    let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2])
                    sumR += r; sumG += g; sumB += b
                    let lum = Float(r + g + b) / 3
                    sumSq += lum * lum
                    n += 1
                }
            }
        }
        guard n > 0 else { return (0, 0, 0, 99) }
        let mean = Float(sumR + sumG + sumB) / Float(3 * n)
        let variance = max(0, sumSq / Float(n) - mean * mean)
        return (UInt8(sumR / n), UInt8(sumG / n), UInt8(sumB / n), variance)
    }
}

import Foundation
import Vision
import CoreGraphics

// Vision → MacOcrBlock. Fields align with lenstrans::OcrBlock
// (text / bbox / line_height / color / bg_variance).

struct MacOcrBlock: Sendable {
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
    var masks: [CGRect] = []
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
                let masks = wordMasks(candidate: top, width: width, height: height)
                blocks.append(MacOcrBlock(
                    text: top.string, x: x, y: y, w: max(8, w), h: max(8, h),
                    lineHeight: max(8, h), r: sample.r, g: sample.g, b: sample.b,
                    bgVariance: sample.var, masks: masks))
            }
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]
        req.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([req])
        return blocks
    }

    private static func wordMasks(candidate: VNRecognizedText, width: Int,
                                  height: Int) -> [CGRect] {
        var masks: [CGRect] = []
        let text = candidate.string
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) {
            _, range, _, _ in
            guard let observation = try? candidate.boundingBox(for: range) else { return }
            let box = observation.boundingBox
            masks.append(CGRect(
                x: box.minX * CGFloat(width),
                y: (1 - box.maxY) * CGFloat(height),
                width: box.width * CGFloat(width),
                height: box.height * CGFloat(height)))
        }
        return masks
    }

    private static func sampleColors(bgra: Data, width: Int, height: Int,
                                     x: Int, y: Int, w: Int, h: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, var: Float) {
        let margin = max(2, min(8, h / 3))
        let x0 = max(0, x - margin), y0 = max(0, y - margin)
        let x1 = min(width, x + max(1, w) + margin)
        let y1 = min(height, y + max(1, h) + margin)
        let bucketCount = 8 * 8 * 8
        var counts = [Int](repeating: 0, count: bucketCount)
        var sumsR = [Int](repeating: 0, count: bucketCount)
        var sumsG = [Int](repeating: 0, count: bucketCount)
        var sumsB = [Int](repeating: 0, count: bucketCount)
        var sumsL = [Double](repeating: 0, count: bucketCount)
        var sumsL2 = [Double](repeating: 0, count: bucketCount)
        bgra.withUnsafeBytes { raw in
            guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for yy in y0..<y1 {
                for xx in x0..<x1 {
                    // Sample the ring around glyphs so the replacement uses the source
                    // background, not an average polluted by the text color.
                    if xx >= x, xx < x + w, yy >= y, yy < y + h { continue }
                    let o = (yy * width + xx) * 4
                    let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2])
                    let bucket = (r >> 5) * 64 + (g >> 5) * 8 + (b >> 5)
                    let luminance = Double(r + g + b) / 3
                    counts[bucket] += 1
                    sumsR[bucket] += r; sumsG[bucket] += g; sumsB[bucket] += b
                    sumsL[bucket] += luminance
                    sumsL2[bucket] += luminance * luminance
                }
            }
        }
        guard let bucket = counts.indices.max(by: { counts[$0] < counts[$1] }),
              counts[bucket] > 0 else { return (0, 0, 0, 99) }
        let count = counts[bucket]
        let mean = sumsL[bucket] / Double(count)
        let standardDeviation = sqrt(max(0, sumsL2[bucket] / Double(count) - mean * mean))
        return (UInt8(sumsR[bucket] / count), UInt8(sumsG[bucket] / count),
                UInt8(sumsB[bucket] / count), Float(standardDeviation))
    }
}

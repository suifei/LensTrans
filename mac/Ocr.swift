import Foundation
import Vision

// Vision → lenstrans::OcrBlock. Field names must stay text / bbox / line_height / color / bg_variance.

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
    static func recognize(bgra _: Data, width _: Int, height _: Int) throws -> [MacOcrBlock] {
        // TODO: VNRecognizeTextRequest (zh/en/ja/ko), map to MacOcrBlock.
        throw NSError(domain: "LensTrans", code: 1, userInfo: [NSLocalizedDescriptionKey: "OCR stub"])
    }
}

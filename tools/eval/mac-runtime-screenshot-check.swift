import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("usage: mac-runtime-screenshot-check.swift <png>\n", stderr)
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard let source = CGImageSourceCreateWithURL(url, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("runtime screenshot is not a readable PNG\n", stderr)
    exit(3)
}

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(
    data: &pixels, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
) else {
    fputs("runtime screenshot bitmap allocation failed\n", stderr)
    exit(4)
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var rows = [Int](repeating: 0, count: height)
var columns = [Int](repeating: 0, count: width)
var statusPixels = 0
for y in 0..<height {
    for x in 0..<width {
        let offset = (y * width + x) * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let activeGreen = green > 140 && green > red + 70 && green > blue + 20
        let activeOrange = red > 170 && green > 90 && green < red && blue < 100
        if activeGreen || activeOrange {
            statusPixels += 1
            rows[y] += 1
            columns[x] += 1
        }
    }
}

let longestRow = rows.max() ?? 0
let longestColumn = columns.max() ?? 0
guard statusPixels >= 500, longestRow >= 200, longestColumn >= 100 else {
    fputs("LensTrans status frame not visible: pixels=\(statusPixels) row=\(longestRow) column=\(longestColumn)\n", stderr)
    exit(5)
}
print("runtime screenshot pixels: PASS status=\(statusPixels) row=\(longestRow) column=\(longestColumn)")

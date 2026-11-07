import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not load the composed iOS screenshot")
}
let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
        fatalError("Could not create screenshot decoder")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}
var counts = [Int](repeating: 0, count: 4)
for offset in stride(from: 0, to: pixels.count, by: 4) {
    let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
    if r > 220 && g < 35 && b < 35 { counts[0] += 1 }
    if g > 220 && r < 35 && b < 35 { counts[1] += 1 }
    if b > 220 && r < 35 && g < 35 { counts[2] += 1 }
    if r > 220 && g > 220 && b > 220 { counts[3] += 1 }
}
let minimum = width * height / 100
guard counts.allSatisfy({ $0 >= minimum }) else {
    fatalError("The composed screenshot does not contain all four rendered regions: \(counts), minimum \(minimum)")
}
print("PASS composed iOS screen: red/green/blue/white pixels \(counts)")

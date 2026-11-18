import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Matches ImageCaptureBridge.Request. The engine owns its pointers only for
// the duration of the callback, so never pass this struct into an async task.
nonisolated struct ImageCaptureRequest {
    var pixels: UnsafeRawPointer?
    var filePath: UnsafePointer<CChar>?
    var width: Int32
    var height: Int32
    var byteLength: Int32
    var flags: Int32
    var result: Int32
}

nonisolated enum CaptureImageEncoder {
    static func jpeg(_ request: ImageCaptureRequest) -> Data? {
        let width = Int(request.width), height = Int(request.height)
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let required = Int64(width) * Int64(height) * 4
        guard required <= 64 * 1024 * 1024, Int64(request.byteLength) >= required,
              let pixels = request.pixels else { return nil }
        let bytes = Data(bytes: pixels, count: Int(required))
        let bgra = request.flags & 1 != 0
        let bitmapInfo = CGBitmapInfo(rawValue: bgra
            ? CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            : CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: bytes as CFData),
              var image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        let flipX = request.flags & 2 != 0, flipY = request.flags & 4 != 0
        if flipX || flipY {
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.translateBy(x: flipX ? CGFloat(width) : 0, y: flipY ? CGFloat(height) : 0)
            context.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let transformed = context.makeImage() else { return nil }
            image = transformed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}


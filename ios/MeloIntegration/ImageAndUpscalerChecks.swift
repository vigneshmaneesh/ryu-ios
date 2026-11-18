import Foundation
import CoreGraphics
import ImageIO
import Metal
import MetalFX

@main
struct ImageAndUpscalerChecks {
    static func require(_ success: Bool, _ message: String) {
        precondition(success, message)
    }

    static func main() {
        require(MemoryLayout<ImageCaptureRequest>.size == 36 &&
                MemoryLayout<ImageCaptureRequest>.stride == 40, "Image capture ABI layout changed")
        for flags in 0..<8 {
            let size = 64
            var pixels = [UInt8](repeating: 255, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let colour: [UInt8] = y < size / 2
                        ? (x < size / 2 ? [255, 0, 0] : [0, 255, 0])
                        : (x < size / 2 ? [0, 0, 255] : [255, 255, 255])
                    let offset = (y * size + x) * 4
                    pixels[offset] = colour[flags & 1 != 0 ? 2 : 0]
                    pixels[offset + 1] = colour[1]
                    pixels[offset + 2] = colour[flags & 1 != 0 ? 0 : 2]
                }
            }
            let jpeg = pixels.withUnsafeBytes { bytes in
                CaptureImageEncoder.jpeg(ImageCaptureRequest(pixels: bytes.baseAddress, filePath: nil,
                    width: Int32(size), height: Int32(size), byteLength: Int32(pixels.count),
                    flags: Int32(flags), result: 0))
            }
            require(jpeg != nil, "JPEG encoding failed for flags \(flags)")
            let source = CGImageSourceCreateWithData(jpeg! as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            var decoded = [UInt8](repeating: 0, count: size * size * 4)
            decoded.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                    bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
            // A CG bitmap context stores rows in the same order as the input
            // provider. Compare interior pixels, allowing JPEG rounding.
            for y in [8, 56] {
                for x in [8, 56] {
                    let originalX = flags & 2 != 0 ? size - 1 - x : x
                    let originalY = flags & 4 != 0 ? size - 1 - y : y
                    let expected: [Int] = originalY < size / 2
                        ? (originalX < size / 2 ? [255, 0, 0] : [0, 255, 0])
                        : (originalX < size / 2 ? [0, 0, 255] : [255, 255, 255])
                    for channel in 0..<3 {
                        let actual = Int(decoded[(y * size + x) * 4 + channel])
                        require(abs(actual - expected[channel]) < 35,
                                "Wrong colour/orientation: flags \(flags), \(x),\(y), channel \(channel): \(actual)")
                    }
                }
            }
        }
        require(CaptureImageEncoder.jpeg(ImageCaptureRequest(pixels: nil, filePath: nil,
            width: 0, height: 0, byteLength: 0, flags: 0, result: 0)) == nil, "Invalid image accepted")
        print("PASS JPEG colours, RGBA/BGRA, all flips, owned data and capture ABI")

        guard #available(macOS 26.0, *), let device = MTLCreateSystemDefaultDevice(),
              MTLFXSpatialScalerDescriptor.supportsMetal4FX(device) else {
            print("SKIP Metal 4 GPU execution: runner does not expose a supported GPU")
            return
        }
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = 64
        descriptor.inputHeight = 64
        descriptor.outputWidth = 128
        descriptor.outputHeight = 128
        descriptor.colorTextureFormat = .rgba8Unorm
        descriptor.outputTextureFormat = .rgba8Unorm
        descriptor.colorProcessingMode = .perceptual
        guard let backend = Metal4SpatialUpscaler(device: device, descriptor: descriptor),
              let queue = device.makeCommandQueue() else {
            fatalError("Supported Metal 4 spatial backend failed to initialize")
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 64, height: 64, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = backend.scaler.colorTextureUsage
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 128, height: 128, mipmapped: false)
        outputDescriptor.storageMode = .private
        outputDescriptor.usage = backend.scaler.outputTextureUsage
        let input = device.makeTexture(descriptor: inputDescriptor)!
        let output = device.makeTexture(descriptor: outputDescriptor)!
        let readback = device.makeBuffer(length: 128 * 128 * 4, options: .storageModeShared)!
        for iteration in 0..<8 {
            var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                pixels[i + (iteration % 2)] = 255
                pixels[i + 3] = 255
            }
            pixels.withUnsafeBytes { bytes in
                input.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0,
                              withBytes: bytes.baseAddress!, bytesPerRow: 64 * 4)
            }
            let completion = queue.makeCommandBuffer()!
            require(backend.encode(legacyQueue: queue, completionBuffer: completion,
                                   input: input, output: output, width: 64, height: 64), "GPU encode failed")
            let blit = completion.makeBlitCommandEncoder()!
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: 128, height: 128, depth: 1),
                      to: readback, destinationOffset: 0, destinationBytesPerRow: 128 * 4,
                      destinationBytesPerImage: 128 * 128 * 4)
            blit.endEncoding()
            completion.commit()
            completion.waitUntilCompleted()
            require(completion.status == .completed, "GPU command failed: \(String(describing: completion.error))")
            let result = readback.contents().assumingMemoryBound(to: UInt8.self)
            let offset = (64 * 128 + 64) * 4
            require(result[offset + (iteration % 2)] > 220 &&
                    result[offset + (1 - iteration % 2)] < 30, "Stale or incorrect upscaler output")
        }
        print("PASS Metal 4 spatial GPU readback, cross-queue synchronization and allocator reuse")
    }
}

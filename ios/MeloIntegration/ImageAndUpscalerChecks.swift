import Foundation
import CoreGraphics
import ImageIO
import Metal
import MetalFX
import MetalPerformanceShaders

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

        if let device = MTLCreateSystemDefaultDevice(), MPSSupportsMTLDevice(device) {
            checkDirectResize(device: device)
        } else {
            print("SKIP direct resize GPU execution: runner does not expose a supported GPU")
        }

        guard #available(macOS 26.0, *), let device = MTLCreateSystemDefaultDevice(),
              MTLFXSpatialScalerDescriptor.supportsMetal4FX(device) else {
            print("SKIP Metal 4 GPU execution: runner does not expose a supported GPU")
            return
        }
        checkMetal4(device: device, width: 64, height: 64, format: .rgba8Unorm)
        checkMetal4(device: device, width: 427, height: 240, format: .bgra8Unorm)
        print("PASS Metal 4 spatial readback, including the 427x240 case and overlapping presentation submissions")
    }

    private static func checkDirectResize(device: any MTLDevice) {
        let queue = device.makeCommandQueue()!
        let format = MTLPixelFormat.bgra8Unorm
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: 32, height: 24, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = device.makeTexture(descriptor: inputDescriptor)!
        let pixels = (0..<(32 * 24 * 4)).map { UInt8(truncatingIfNeeded: $0 * 13 + $0 / 128) }
        pixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, 32, 24), mipmapLevel: 0,
                          withBytes: $0.baseAddress!, bytesPerRow: 32 * 4)
        }
        let width = 61
        let height = 43
        let stride = (width * 4 + 255) / 256 * 256
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        outputDescriptor.storageMode = .private
        outputDescriptor.usage = .shaderWrite
        let intermediate = device.makeTexture(descriptor: outputDescriptor)!
        let fast = device.makeTexture(descriptor: outputDescriptor)!
        let results = (0..<2).map { _ in
            device.makeBuffer(length: stride * height, options: .storageModeShared)!
        }
        let buffer = queue.makeCommandBuffer()!
        let scaler = MPSImageLanczosScale(device: device)
        require(!MetalFxPresentation.encodeDirectResize(scaler, commandBuffer: buffer, source: input,
            destination: fast, x: 1, y: 0, width: width - 1, height: height), "Inset viewport must use the offset copy")
        require(MetalFxPresentation.encodeDirectResize(scaler, commandBuffer: buffer, source: input,
            destination: fast, x: 0, y: 0, width: width, height: height), "Full viewport should resize directly")
        scaler.encode(commandBuffer: buffer, sourceTexture: input, destinationTexture: intermediate)

        let blit = buffer.makeBlitCommandEncoder()!
        for (texture, output) in zip([fast, intermediate], results) {
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: output, destinationOffset: 0, destinationBytesPerRow: stride,
                      destinationBytesPerImage: stride * height)
        }
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        require(buffer.status == .completed, "Lanczos resize: \(String(describing: buffer.error))")
        for y in 0..<height {
            let offset = y * stride
            let actual = Data(bytes: results[0].contents().advanced(by: offset), count: width * 4)
            let expected = Data(bytes: results[1].contents().advanced(by: offset), count: width * 4)
            require(actual == expected, "Direct resize differed from the intermediate at row \(y)")
        }
        print("PASS direct MetalFX presentation resize pixel comparison and inset fallback")
    }

    @available(macOS 26.0, *)
    private static func checkMetal4(device: any MTLDevice, width: Int, height: Int, format: MTLPixelFormat) {
        let outputWidth = width * 2
        let outputHeight = height * 2
        let readbackStride = (outputWidth * 4 + 255) / 256 * 256
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = width
        descriptor.inputHeight = height
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorTextureFormat = format
        descriptor.outputTextureFormat = format
        descriptor.colorProcessingMode = .perceptual
        guard let backend = Metal4SpatialUpscaler(device: device, descriptor: descriptor),
              let queue = device.makeCommandQueue() else {
            fatalError("Supported Metal 4 spatial backend failed to initialize")
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: width, height: height, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = backend.scaler.colorTextureUsage
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: outputWidth, height: outputHeight, mipmapped: false)
        outputDescriptor.storageMode = .private
        outputDescriptor.usage = backend.scaler.outputTextureUsage
        let output = device.makeTexture(descriptor: outputDescriptor)!
        let inputs = (0..<3).map { channel in
            let input = device.makeTexture(descriptor: inputDescriptor)!
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                pixels[i + channel] = 255
                pixels[i + 3] = 255
            }
            pixels.withUnsafeBytes { bytes in
                input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                              withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
            }
            return input
        }
        let readbacks = inputs.map { _ in
            device.makeBuffer(length: readbackStride * outputHeight, options: .storageModeShared)!
        }
        for batch in 0..<3 {
            let buffers = inputs.indices.map { index in
                let channel = (batch + index) % inputs.count
                let completion = queue.makeCommandBuffer()!
                require(backend.encode(legacyQueue: queue, completionBuffer: completion,
                                       input: inputs[channel], output: output, width: width, height: height) {
                    let blit = completion.makeBlitCommandEncoder()!
                    blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                              sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                              sourceSize: MTLSize(width: outputWidth, height: outputHeight, depth: 1),
                              to: readbacks[index], destinationOffset: 0, destinationBytesPerRow: readbackStride,
                              destinationBytesPerImage: readbackStride * outputHeight)
                    blit.endEncoding()
                }, "GPU encode failed")
                completion.commit()
                return completion
            }
            for (index, completion) in buffers.enumerated() {
                completion.waitUntilCompleted()
                require(completion.status == .completed, "GPU command failed: \(String(describing: completion.error))")
                let result = readbacks[index].contents().assumingMemoryBound(to: UInt8.self)
                let offset = height * readbackStride + width * 4
                let channel = (batch + index) % inputs.count
                require(result[offset + channel] > 220 &&
                        result[offset + (channel + 1) % 3] < 30, "Stale or incorrect upscaler output")
            }
        }
    }
}

import Metal
import MetalPerformanceShaders

nonisolated enum MetalFxPresentation {
    static func encodeDirectResize(
        _ scaler: MPSImageLanczosScale, commandBuffer: any MTLCommandBuffer,
        source: any MTLTexture, destination: any MTLTexture,
        x: Int, y: Int, width: Int, height: Int
    ) -> Bool {
        // Use the same Lanczos resize with a full-size drawable as its output.
        // Inset views use the existing intermediate texture and offset copy.
        guard x == 0, y == 0, width == destination.width, height == destination.height,
              !destination.isFramebufferOnly, destination.usage.contains(.shaderWrite),
              source.pixelFormat == destination.pixelFormat,
              destination.pixelFormat == .bgra8Unorm || destination.pixelFormat == .rgba8Unorm else {
            return false
        }

        scaler.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
        return true
    }
}

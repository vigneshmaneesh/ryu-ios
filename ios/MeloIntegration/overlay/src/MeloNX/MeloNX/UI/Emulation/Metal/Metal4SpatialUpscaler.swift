import Foundation
import Metal
import MetalFX

// MetalFX uses the current OS implementation. Prefer its Metal 4 command path
// where supported, while retaining the original path for incompatible devices.
@available(iOS 26.0, macOS 26.0, *)
nonisolated final class Metal4SpatialUpscaler {
    private final class Frame {
        let allocator: any MTL4CommandAllocator
        let buffer: any MTL4CommandBuffer
        let residency: any MTLResidencySet

        init?(device: any MTLDevice) {
            guard let allocator = device.makeCommandAllocator(),
                  let buffer = device.makeCommandBuffer(),
                  let residency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()) else { return nil }
            self.allocator = allocator
            self.buffer = buffer
            self.residency = residency
        }
    }

    let scaler: any MTL4FXSpatialScaler
    private let queue: any MTL4CommandQueue
    private let compiler: any MTL4Compiler
    private let event: any MTLEvent
    private var eventValue: UInt64 = 0
    private let available = DispatchSemaphore(value: 3)
    private let poolLock = NSLock()
    private var freeFrames: [Frame]

    init?(device: any MTLDevice, descriptor: MTLFXSpatialScalerDescriptor) {
        guard MTLFXSpatialScalerDescriptor.supportsMetal4FX(device),
              let queue = device.makeMTL4CommandQueue(),
              let event = device.makeEvent(),
              let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()),
              let scaler = descriptor.makeSpatialScaler(device: device, compiler: compiler) else { return nil }
        var frames: [Frame] = []
        for _ in 0..<3 {
            guard let frame = Frame(device: device) else { return nil }
            frames.append(frame)
        }
        self.queue = queue
        self.event = event
        self.compiler = compiler
        self.scaler = scaler
        self.freeFrames = frames
        queue.label = "MeloNX Metal 4 spatial upscaler"
    }

    // The completion buffer stays on the original MoltenVK queue. It waits for
    // this upscale before doing presentation work, so Vulkan's present cannot
    // overtake MetalFX and MetalFX cannot overwrite the preceding frame's output.
    func encode(legacyQueue: any MTLCommandQueue, completionBuffer: any MTLCommandBuffer,
                input: any MTLTexture, output: any MTLTexture, width: Int, height: Int) -> Bool {
        guard available.wait(timeout: .now() + .milliseconds(50)) == .success else { return false }
        poolLock.lock()
        let frame = freeFrames.removeLast()
        poolLock.unlock()
        guard let producer = legacyQueue.makeCommandBuffer() else {
            recycle(frame)
            return false
        }

        frame.allocator.reset()
        frame.residency.removeAllAllocations()
        if let heap = input.heap { frame.residency.addAllocation(heap) }
        else { frame.residency.addAllocation(input) }
        if let heap = output.heap { frame.residency.addAllocation(heap) }
        else { frame.residency.addAllocation(output) }
        frame.residency.commit()

        eventValue += 2
        let ready = eventValue - 1, finished = eventValue
        producer.label = "MeloNX Metal 4 input dependency"
        producer.encodeSignalEvent(event, value: ready)
        producer.commit()

        queue.waitForEvent(event, value: ready)
        frame.buffer.beginCommandBuffer(allocator: frame.allocator)
        frame.buffer.useResidencySet(frame.residency)
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.inputContentWidth = width
        scaler.inputContentHeight = height
        scaler.encode(commandBuffer: frame.buffer)
        frame.buffer.endCommandBuffer()
        queue.commit([frame.buffer])
        queue.signalEvent(event, value: finished)

        completionBuffer.encodeWaitForEvent(event, value: finished)
        // Metal 4 command buffers do not retain resource objects. Hold every
        // input, allocator and residency set until this dependent work completes.
        completionBuffer.addCompletedHandler { [self, frame, input, output] _ in
            withExtendedLifetime((input, output)) { recycle(frame) }
        }
        scaler.colorTexture = nil
        scaler.outputTexture = nil
        return true
    }

    private func recycle(_ frame: Frame) {
        poolLock.lock()
        freeFrames.append(frame)
        poolLock.unlock()
        available.signal()
    }
}

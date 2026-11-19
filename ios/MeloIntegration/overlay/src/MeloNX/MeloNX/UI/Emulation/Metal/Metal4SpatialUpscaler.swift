import Foundation
import Metal
import MetalFX

// MetalFX spatial scaling submitted through a separate Metal 4 command queue.
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
    private let presentationEvent: any MTLEvent
    private let scaleEvent: any MTLEvent
    private var frameNumber: UInt64 = 0
    private let available = DispatchSemaphore(value: 3)
    private let poolLock = NSLock()
    private var freeFrames: [Frame]
    private var presentationFailed = false

    var hasFailed: Bool {
        poolLock.lock()
        defer { poolLock.unlock() }
        return presentationFailed
    }

    init?(device: any MTLDevice, descriptor: MTLFXSpatialScalerDescriptor) {
        guard MTLFXSpatialScalerDescriptor.supportsMetal4FX(device),
              let queue = device.makeMTL4CommandQueue(),
              let presentationEvent = device.makeEvent(),
              let scaleEvent = device.makeEvent(),
              let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()),
              let scaler = descriptor.makeSpatialScaler(device: device, compiler: compiler) else { return nil }
        var frames: [Frame] = []
        for _ in 0..<3 {
            guard let frame = Frame(device: device) else { return nil }
            frames.append(frame)
        }
        self.queue = queue
        self.presentationEvent = presentationEvent
        self.scaleEvent = scaleEvent
        self.compiler = compiler
        self.scaler = scaler
        self.freeFrames = frames
    }

    // Call serially. The caller commits the completion buffer after this method
    // encodes the presentation work and its completion signal.
    func encode(legacyQueue: any MTLCommandQueue, completionBuffer: any MTLCommandBuffer,
                input: any MTLTexture, output: any MTLTexture, width: Int, height: Int,
                encodePresentation: () -> Void) -> Bool {
        guard available.wait(timeout: .now() + .milliseconds(50)) == .success else { return false }
        poolLock.lock()
        if presentationFailed {
            poolLock.unlock()
            available.signal()
            return false
        }
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

        frameNumber += 1
        let presented = frameNumber * 2
        let ready = presented - 1
        producer.label = "MeloNX Metal 4 input dependency"
        if frameNumber > 1 {
            // The output texture is shared between frames. Wait for the prior
            // legacy-queue copy to finish before another Metal 4 write.
            producer.encodeWaitForEvent(presentationEvent, value: presented - 2)
        }
        producer.encodeSignalEvent(presentationEvent, value: ready)
        producer.commit()

        queue.waitForEvent(presentationEvent, value: ready)
        frame.buffer.beginCommandBuffer(allocator: frame.allocator)
        frame.buffer.useResidencySet(frame.residency)
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.inputContentWidth = width
        scaler.inputContentHeight = height
        scaler.encode(commandBuffer: frame.buffer)
        frame.buffer.endCommandBuffer()
        queue.commit([frame.buffer])
        queue.signalEvent(scaleEvent, value: frameNumber)

        completionBuffer.encodeWaitForEvent(scaleEvent, value: frameNumber)
        encodePresentation()
        completionBuffer.encodeSignalEvent(presentationEvent, value: presented)
        // Metal 4 command buffers do not retain resource objects. Hold every
        // input, allocator and residency set until this dependent work completes.
        completionBuffer.addCompletedHandler { [self, frame, input, output] completed in
            if let error = completed.error {
                NSLog("[MetalFX] Metal 4 presentation failed: %@", error.localizedDescription)
                poolLock.lock()
                presentationFailed = true
                poolLock.unlock()
            }
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

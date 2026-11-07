import Combine
import Foundation

@MainActor
final class BackendChecks: ObservableObject {
    @Published var isRunning = false
    @Published var report = ""
    @Published var passed = false

    func run() {
        guard !isRunning else { return }
        isRunning = true
        passed = false
        report = "Initializing the emulated filesystem and checking GPU readback…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message: String
            var status: Int32 = -1
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                var directory = support.appendingPathComponent("RyuCore", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                var buffer = [CChar](repeating: 0, count: 4096)
                status = directory.path.withCString { path in
                    buffer.withUnsafeMutableBufferPointer { output in
                        ryu_backend_check(path, output.baseAddress, output.count)
                    }
                }
                message = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if message.isEmpty { message = "Backend checks returned \(status)." }
            } catch {
                message = "Could not initialize app storage: \(error.localizedDescription)"
            }
            let completedStatus = status
            let completedMessage = message
            Task { @MainActor in
                self?.isRunning = false
                self?.passed = completedStatus == 0
                self?.report = completedMessage
            }
        }
    }
}

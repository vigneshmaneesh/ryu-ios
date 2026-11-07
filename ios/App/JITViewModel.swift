import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class JITViewModel: ObservableObject {
    @Published var status = "Ready to test"
    @Published var detail = "Connect LocalDevVPN, then enable JIT to run the ARM64 test."
    @Published var isRunning = false
    @Published var passed = false
    @Published var result: UInt64?
    @Published var bias: UInt32 = 42
    @Published var txm = Int32(-1)
    @Published var entitlement = Int32(-1)
    @Published var logs: [String] = []
    @Published var needsRestart = false
    @Published var guestReport = ""
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastStage = Int32(-1)

    init() { refreshEnvironment() }

    func refreshEnvironment() {
        txm = ryu_txm_presence()
        entitlement = ryu_debug_entitlement()
    }

    private func log(_ message: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("\(time)  \(message)")
    }

    private var coreProvenance: String {
        guard let url = Bundle.main.url(forResource: "upstream.lock", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lock = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let revision = lock["revision"] as? String,
              let abi = lock["adapterAbi"] as? Int else { return "Unavailable" }
        return "\(revision); core ABI \(abi)"
    }

    var diagnostics: String {
        "Ryu iOS production CPU prototype \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))\n" +
        "System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n" +
        "Device: \(UIDevice.current.model)\n" +
        "Physical RAM: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MiB\n" +
        "App footprint: \(ryu_memory_footprint() / 1_048_576) MiB; available: \(ryu_available_memory() / 1_048_576) MiB\n" +
        "Prepared code region: \(ryu_prepared_code_capacity() / 1_048_576) MiB\n" +
        "Upstream: \(coreProvenance)\n" +
        "TXM: \(txm), get-task-allow: \(entitlement)\n" +
        "Status: \(status)\n\(detail)\n\n" + logs.joined(separator: "\n")
    }

    func start() {
        guard !isRunning, !needsRestart else { return }
        refreshEnvironment()
        guard entitlement == 1 else {
            status = "Signing needs attention"
            detail = "Reinstall this IPA with AltStore Classic or SideStore. The installed app needs get-task-allow."
            return
        }
        guard txm != -1 else {
            status = "Could not check JIT requirements"
            detail = "TXM status is unknown. Share diagnostics so this device can be investigated."
            return
        }
        let alreadyReady = ryu_jit_ready() == 1
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundleID),
            URLQueryItem(name: "pid", value: String(ProcessInfo.processInfo.processIdentifier))
        ]
        if txm == 1 {
            components.queryItems?.append(URLQueryItem(name: "script-name", value: "universal.js"))
        }
        guard let url = components.url else { return }

        bias = UInt32.random(in: 0...UInt32.max)
        let requestedBias = bias
        let requestedTXM = txm
        passed = false
        result = nil
        guestReport = ""
        isRunning = true
        lastStage = -1
        status = alreadyReady ? "Generating new ARM64 code" : "Waiting for StikDebug"
        detail = alreadyReady ? "Reusing the prepared memory with a new function." : "Allow StikDebug to enable JIT, then return here."
        log("Starting f(a, b) = a + b + \(requestedBias).")
        log("Before: footprint \(ryu_memory_footprint() / 1_048_576) MiB, available \(ryu_available_memory() / 1_048_576) MiB.")
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare Ryujinx JIT") { [weak self] in
            Task { @MainActor in
                ryu_jit_cancel()
                self?.log("Background time expired; waiting was cancelled.")
                self?.endBackgroundTask()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStage() }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var value: UInt64 = 0
            var error = [CChar](repeating: 0, count: 2048)
            let code = error.withUnsafeMutableBufferPointer { buffer in
                ryu_jit_run(requestedTXM, 120_000, requestedBias, &value, buffer.baseAddress, buffer.count)
            }
            let message = error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            let completedValue = value
            Task { @MainActor in self?.finish(code: code, value: completedValue, message: message) }
        }

        if !alreadyReady {
            UIApplication.shared.open(url) { [weak self] opened in
                Task { @MainActor in
                    guard let self else { return }
                    self.log(opened ? "Opened StikDebug for this process." : "iOS could not open StikDebug.")
                    if !opened { ryu_jit_cancel() }
                }
            }
        }
    }

    func cancel() { ryu_jit_cancel() }

    private func updateStage() {
        let stage = ryu_jit_stage()
        guard stage != lastStage else { return }
        lastStage = stage
        let messages: [Int32: String] = [
            1: "Waiting for debugger", 2: "Preparing executable memory",
            3: "Generating ARM64 code", 4: "Executing generated code",
            5: "Production CPU passed", 6: "Test failed", 7: "Cancelled",
            8: "Translating guest programs", 9: "Executing translated guest code"
        ]
        if let message = messages[stage] { status = message; log(message) }
    }

    private func finish(code: Int32, value: UInt64, message: String) {
        updateStage()
        timer?.invalidate()
        timer = nil
        isRunning = false
        endBackgroundTask()
        log("After: footprint \(ryu_memory_footprint() / 1_048_576) MiB, available \(ryu_available_memory() / 1_048_576) MiB.")
        if code == 0 {
            passed = true
            result = value
            status = "Production CPU passed"
            detail = "The arithmetic probe, 25 compiler cases and all 5 production CPU groups passed."
            guestReport = message
            log(message)
            log("Verified result: 20 + 22 + \(bias) = \(value).")
        } else {
            status = ryu_jit_stage() == 7 ? "Cancelled" : "JIT test failed"
            detail = message.isEmpty ? "Native test returned error \(code)." : message
            needsRestart = ryu_jit_stage() == 6
            log(detail)
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

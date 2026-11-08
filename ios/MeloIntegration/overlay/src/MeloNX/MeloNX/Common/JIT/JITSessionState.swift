import Foundation

// Process-local state: a debugger round trip is a request, not proof that
// executable memory is ready. Only the native allocator can mark this ready.
@MainActor
final class JITSessionState {
    private(set) var isReady = false
    private(set) var activationRequested = false
    private var preparing = false

    func beginActivation(explicitRetry: Bool = false) -> Bool {
        guard !isReady, !activationRequested || explicitRetry else { return false }
        activationRequested = true
        return true
    }

    func activationFailed() { activationRequested = false }

    func checkReady(debuggerAttached: Bool, prepare: () -> Bool) -> Bool {
        if isReady { return true }
        guard debuggerAttached, !preparing else { return false }
        preparing = true
        defer { preparing = false }
        isReady = prepare()
        return isReady
    }

    static func stikDebugURL(bundleIdentifier: String, pid: Int32,
                             legacyScript: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundleIdentifier),
            URLQueryItem(name: "pid", value: String(pid)),
            URLQueryItem(name: "script-name", value: legacyScript == nil ? "universal.js" : "MeloNX")
        ]
        if let legacyScript {
            components.queryItems?.append(URLQueryItem(name: "script-data", value: legacyScript))
        }
        return components.url
    }
}

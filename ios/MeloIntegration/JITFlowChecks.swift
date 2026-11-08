import Foundation

@main
struct JITFlowChecks {
    @MainActor static func main() {
        let state = JITSessionState()
        var providerOpens = 0, preparations = 0
        func request(_ explicitRetry: Bool = false) {
            if state.beginActivation(explicitRetry: explicitRetry) { providerOpens += 1 }
        }
        func check(attached: Bool, success: Bool) -> Bool {
            state.checkReady(debuggerAttached: attached) { preparations += 1; return success }
        }
        request()
        for _ in 0..<20 {
            precondition(!check(attached: false, success: true))
            request() // Another view appearance/return from the provider.
        }
        precondition(providerOpens == 1 && preparations == 0,
                     "Activation return must not reopen the provider or allocate before attachment.")
        precondition(!check(attached: true, success: false))
        request()
        precondition(providerOpens == 1 && !state.isReady,
                     "Allocator failure must remain pending without an automatic redirect.")
        request(true)
        precondition(providerOpens == 2, "Explicit retry must remain available.")
        precondition(check(attached: true, success: true))
        let completedPreparations = preparations
        precondition(check(attached: false, success: false))
        request(true)
        precondition(preparations == completedPreparations && providerOpens == 2,
                     "Prepared memory must remain ready after debugger detachment.")
        let restarted = JITSessionState()
        precondition(!restarted.isReady && restarted.beginActivation(),
                     "Readiness must never persist across a process restart.")
        restarted.activationFailed()
        precondition(restarted.beginActivation(), "Failed provider opens must be retryable.")
        let nested = JITSessionState()
        precondition(nested.checkReady(debuggerAttached: true) {
            precondition(!nested.checkReady(debuggerAttached: true) {
                preconditionFailure("Reentrant native allocation.")
            })
            return true
        })
        let url = JITSessionState.stikDebugURL(bundleIdentifier: "app.fow.explorer", pid: 1234)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        precondition(components.scheme == "stikdebug" && components.host == "enable-jit")
        precondition(values["bundle-id"] == "app.fow.explorer" && values["pid"] == "1234")
        precondition(values["script-name"] == "universal.js" && values["script-data"] == nil)
        print("PASS JIT activation: single handoff, explicit retry, allocation gating, detached readiness, process reset, reentrancy and current-process script URL.")
    }
}

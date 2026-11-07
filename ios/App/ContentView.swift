import SwiftUI

struct ContentView: View {
    @StateObject private var model = JITViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.tint)
                        Text("Ryujinx on iOS")
                            .font(.largeTitle.bold())
                        Text("Production CPU · v0.3")
                            .font(.title3).foregroundStyle(.secondary)
                        Text("Tests the production dispatcher, cache invalidation, guest page tables, interrupts and two guest threads. Game loading and graphics are still being developed.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(model.status, systemImage: model.passed ? "checkmark.circle.fill" : "bolt.circle")
                                .font(.headline)
                                .foregroundStyle(model.passed ? Color.green : Color.primary)
                            Text(model.detail).foregroundStyle(.secondary)
                            if !model.guestReport.isEmpty {
                                Text(model.guestReport)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            if let result = model.result {
                                Text("20 + 22 + \(model.bias) = \(result)")
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            if model.isRunning { ProgressView().frame(maxWidth: .infinity) }
                            Button(action: model.start) {
                                Text(model.passed ? "Run another test" : "Enable JIT and test")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isRunning || model.needsRestart)
                            if model.isRunning {
                                Button("Cancel waiting", action: model.cancel)
                                    .disabled(ryu_jit_stage() != 1)
                            }
                            if model.needsRestart {
                                Text("Close this app completely and reopen it before retrying.")
                                    .font(.callout)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Your setup") {
                        VStack(spacing: 12) {
                            LabeledContent("Development signing", value: signingDescription)
                            LabeledContent("Memory protection (TXM)", value: txmDescription)
                            LabeledContent("JIT enabler", value: "StikDebug")
                        }.padding(.top, 8)
                    }
                    Text("Use your existing AltStore, StikDebug and LocalDevVPN setup. Connect the VPN before starting the test.")
                        .font(.callout).foregroundStyle(.secondary)

                    if !model.logs.isEmpty {
                        GroupBox("Diagnostics") {
                            Text(model.logs.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).padding(.top, 8)
                        }
                    }
                    ShareLink(item: model.diagnostics) {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ryu JIT")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.teal)
        }
    }

    private var signingDescription: String {
        switch model.entitlement {
        case 1: "Ready"
        case 0: "Needs reinstallation"
        default: "Unknown"
        }
    }

    private var txmDescription: String {
        switch model.txm {
        case 1: "Present"
        case 0: "Absent"
        default: "Unknown"
        }
    }
}

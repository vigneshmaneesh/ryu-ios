import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = JITViewModel()
    @StateObject private var backend = BackendChecks()
    @StateObject private var horizon = BackendChecks()
    @StateObject private var library = GameLibrary()
    @State private var showingImporter = false

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
                        Text("Horizon homebrew · v0.5")
                            .font(.title3).foregroundStyle(.secondary)
                        Text("Tests the production dispatcher, cache invalidation, guest page tables, interrupts and two guest threads. Game loading and graphics are still being developed.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Game library") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("First compatibility target: Tomodachi Life: Living the Dream")
                                .font(.callout)
                            ForEach(library.titles) { title in
                                HStack {
                                    Image(systemName: "gamecontroller")
                                    VStack(alignment: .leading) {
                                        Text(title.name)
                                        Text(ByteCountFormatter.string(fromByteCount: title.byteCount, countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !library.message.isEmpty {
                                Text(library.message).font(.callout).textSelection(.enabled)
                            }
                            if library.isImporting { ProgressView() }
                            Button("Import game or homebrew") { showingImporter = true }
                                .buttonStyle(.bordered)
                                .disabled(library.isImporting || model.isRunning || backend.isRunning || horizon.isRunning)
                            Text("Files are copied into this app. Game execution is still being developed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
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
                            .disabled(model.isRunning || model.needsRestart || backend.isRunning || library.isImporting || horizon.isRunning || horizon.needsRestart)
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

                    GroupBox("Filesystem and Vulkan backend") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Checks emulated account persistence and an offscreen GPU image through MoltenVK and Metal. These checks do not run a game.")
                                .foregroundStyle(.secondary)
                            if !backend.report.isEmpty {
                                Text(backend.report)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(backend.passed ? Color.green : Color.primary)
                                    .textSelection(.enabled)
                            }
                            if backend.isRunning { ProgressView() }
                            Button("Test platform backends", action: backend.run)
                                .buttonStyle(.bordered)
                                .disabled(model.isRunning || backend.isRunning || library.isImporting || horizon.isRunning || horizon.needsRestart)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Bundled homebrew") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Boots a small NRO through the real Horizon kernel. It requests a heap, prints a marker and exits. Run the JIT test first.")
                                .foregroundStyle(.secondary)
                            if !horizon.report.isEmpty {
                                Text(horizon.report)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(horizon.passed ? Color.green : Color.primary)
                                    .textSelection(.enabled)
                            }
                            if horizon.isRunning { ProgressView() }
                            Button("Boot bundled homebrew", action: horizon.runHorizon)
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.passed || model.isRunning || backend.isRunning || library.isImporting || horizon.isRunning || horizon.needsRestart)
                            if horizon.needsRestart {
                                Text("Close and reopen this app before further execution tests.")
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
                    ShareLink(item: model.diagnostics + "\n\nPlatform backends:\n" + backend.report + "\n\nHorizon homebrew:\n" + horizon.report) {
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
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item],
                allowsMultipleSelection: true, onCompletion: library.importSelection)
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

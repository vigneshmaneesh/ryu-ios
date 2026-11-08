import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = JITViewModel()
    @StateObject private var backend = BackendChecks()
    @StateObject private var horizon = BackendChecks(isHorizon: true)
    @StateObject private var library = GameLibrary()
    @StateObject private var graphics = GraphicsCheck()
    @StateObject private var guest = GraphicsCheck(isGuest: true)
    @StateObject private var system = SystemFiles()
    @ObservedObject private var appActivity = AppActivity.shared
    @State private var showingImporter = false
    @State private var showingGraphics = false
    @State private var showingGuest = false
    @State private var activeTitle: ImportedTitle?

    private var blocked: Bool {
        model.isRunning || backend.isRunning || horizon.isRunning || guest.isRunning || graphics.isRunning || library.isImporting || system.isBusy || appActivity.pending > 0 ||
        model.needsRestart || horizon.needsRestart || guest.needsRestart || graphics.needsRestart
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ryu").font(.largeTitle.bold())
                        Text("Play on iPhone and iPad").font(.title3)
                        Text("Development build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"). Commercial game compatibility is still being developed.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    GroupBox("JIT") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(model.passed ? "JIT ready" : model.status, systemImage: model.passed ? "checkmark.circle.fill" : "bolt.fill")
                                .foregroundStyle(model.passed ? Color.green : Color.primary)
                            if !model.passed { Text(model.detail).font(.callout).foregroundStyle(.secondary) }
                            if model.isRunning { ProgressView() }
                            if !model.passed {
                                Button("Enable JIT with StikDebug", action: model.start)
                                    .buttonStyle(.borderedProminent).disabled(blocked)
                            }
                            if model.isRunning { Button("Cancel waiting", action: model.cancel).disabled(ryu_jit_stage() != 1) }
                            if model.needsRestart || horizon.needsRestart || guest.needsRestart || graphics.needsRestart {
                                Text("Close and reopen the app before launching again.").font(.callout)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Ryu Catch") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("A playable Switch homebrew game", systemImage: "gamecontroller.fill").font(.headline)
                            Text("Move your ship and collect targets. Use the touch stick, tap the game screen, or connect a controller. A boosts and beeps; B resets. Green pips show your score.")
                                .foregroundStyle(.secondary)
                            Button("Play Ryu Catch") { activeTitle = nil; guest.programURL = nil; guest.displayTitle = "Ryu Catch"; showingGuest = true }
                                .buttonStyle(.borderedProminent).disabled(!model.passed || blocked)
                            if !model.passed { Text("Enable JIT to play.").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LibraryPanel(library: library, blocked: blocked, jitReady: model.passed, importGames: { showingImporter = true }) { title, executable in
                        activeTitle = title; guest.programURL = executable; guest.displayTitle = title.name; showingGuest = true
                    }
                    SystemFilesPanel(system: system, blocked: blocked)
                    NavigationLink("User profiles") { ProfilesView() }.disabled(blocked)
                    NavigationLink("Save manager") { SavesView() }.disabled(blocked)
                    DisclosureGroup("Diagnostics and backend checks") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("First commercial compatibility target: Tomodachi Life: Living the Dream").font(.callout)
                            Text(model.diagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            if !guest.report.isEmpty { Text(guest.report).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Button("Test platform backends", action: backend.run).disabled(blocked)
                            if !backend.report.isEmpty { Text(backend.report).font(.caption).textSelection(.enabled) }
                            Button("Test renderer display") { showingGraphics = true }.disabled(blocked)
                            if !graphics.report.isEmpty { Text(graphics.report).font(.caption).textSelection(.enabled) }
                            Button("Boot kernel probe", action: horizon.runHorizon).disabled(!model.passed || blocked)
                            if !horizon.report.isEmpty { Text(horizon.report).font(.caption).textSelection(.enabled) }
                        }.padding(.top, 12)
                    }
                    ShareLink(item: model.diagnostics + "\n\nGame session:\n" + guest.report + "\n\nBackends:\n" + backend.report + "\n\nRenderer:\n" + graphics.report + "\n\nKernel:\n" + horizon.report) {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                    Text("Use your existing AltStore, StikDebug and LocalDevVPN setup.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ryu").navigationBarTitleDisplayMode(.inline).tint(.teal)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsEditor() } label: { Image(systemName: "gearshape") }.disabled(blocked) } }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: library.importSelection)
            .fullScreenCover(isPresented: $showingGraphics) { GraphicsDisplay(model: graphics) }
            .fullScreenCover(isPresented: $showingGuest) { GraphicsDisplay(model: guest) }
            .onChange(of: guest.isRunning) { _, running in
                if running { if let activeTitle { library.beginPlaying(activeTitle) } }
                else { library.endPlaying() }
            }
        }
    }
}

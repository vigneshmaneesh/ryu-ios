import SwiftUI
import Foundation
import CryptoKit

enum SessionControl {
    @discardableResult static func send(_ command: Int32, _ value: Double = 0, _ text: String = "") -> Int32 { text.withCString { ryu_session_command(command, value, $0) } }
    static func configuration(_ program: URL?) -> [String: Any] {
        guard let root = try? AppService.root().appendingPathComponent("settings", isDirectory: true) else { return [:] }
        var result: [String: Any] = [:]
        var names = ["global"]
        if let program { names.append(SHA256.hash(data: Data(program.path.utf8)).map { String(format: "%02x", $0) }.joined()) }
        for name in names {
            if let data = try? Data(contentsOf: root.appendingPathComponent(name + ".json")), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let values = object["values"] as? [String: Any] { result.merge(values) { _, new in new } }
        }
        return result
    }
}

struct PlayMenu: View {
    @ObservedObject var model: GraphicsCheck
    let paused: Bool
    let pause: () -> Void
    let stop: () -> Void
    @State private var volume = 1.0
    @State private var scale = 1.0
    @State private var docked = false
    @State private var resumeAfterScan = false
    var body: some View {
        Form {
            Section {
                Text(model.displayTitle).font(.headline)
                LabeledContent("Frames", value: String(model.frames)); LabeledContent("Frame rate", value: "\(model.fps) FPS")
                LabeledContent("App memory", value: ByteCountFormatter.string(fromByteCount: Int64(ryu_memory_footprint()), countStyle: .memory))
                Button(paused ? "Resume" : "Pause", action: pause)
                Button("Stop game", role: .destructive, action: stop)
            }
            Section("Quick settings") {
                LabeledContent("Volume", value: volume.formatted(.percent))
                Slider(value: $volume, in: 0...1).onChange(of: volume) { _, value in SessionControl.send(1, value) }
                Picker("Vsync", selection: Binding(get: { model.session.vsync }, set: { SessionControl.send(2, Double($0)) })) { Text("Switch").tag(0); Text("Unbounded").tag(1); Text("Custom").tag(2) }
                Toggle("Docked mode", isOn: $docked).onChange(of: docked) { _, value in SessionControl.send(3, value ? 1 : 0) }
                Stepper("Resolution: \(scale.formatted())×", value: $scale, in: 0.25...8, step: 0.25).onChange(of: scale) { _, value in SessionControl.send(4, value) }
                Text("Quick changes affect this session. Edit the game's settings from the library to save defaults.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Screenshots") {
                Button("Take screenshot") { SessionControl.send(0) }.disabled(paused || model.frames == 0)
                if !model.session.screenshot.isEmpty { ShareLink(item: URL(fileURLWithPath: model.session.screenshot)) { Label("Share latest screenshot", systemImage: "square.and.arrow.up") } }
                NavigationLink("Screenshot gallery") { ScreenshotGallery() }
            }
            Section {
                NavigationLink("Amiibo") { AmiiboView(model: model)
                    .onAppear { if !paused && (SessionControl.configuration(model.programURL)["PauseEmulationWhileScanningAmiibo"] as? Bool ?? true) { resumeAfterScan = true; pause() } }
                    .onDisappear { if resumeAfterScan { resumeAfterScan = false; pause() } }
                }
                NavigationLink("Session log") { SessionLogView() }
                if !model.session.error.isEmpty { Text(model.session.error).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .navigationTitle("Game menu").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let values = SessionControl.configuration(model.programURL)
            volume = Double(model.session.volume)
            scale = (values["ResScale"] as? Double == -1 ? values["ResScaleCustom"] as? Double : values["ResScale"] as? Double) ?? 1
            docked = values["DockedMode"] as? Bool ?? false
        }
    }
}

struct SessionLogView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let path = try? AppService.root().appendingPathComponent("guest-last-run.log")
            let bytes = path.flatMap { try? Data(contentsOf: $0) } ?? Data()
            let text = String(decoding: bytes.suffix(48 * 1024), as: UTF8.self)
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                .toolbar { ShareLink(item: text) { Image(systemName: "square.and.arrow.up") } }
        }.navigationTitle("Session log")
    }
}

struct ScreenshotGallery: View {
    @State private var files: [URL] = []
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(files, id: \.self) { url in
                    VStack { if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit() }; ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up").font(.caption) } }.padding()
                }
                if files.isEmpty { Text("No screenshots yet.").padding() }
            }
        }.navigationTitle("Screenshots").task {
            if let root = try? AppService.root().appendingPathComponent("Screenshots") { files = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
        }
    }
}

struct AmiiboView: View {
    @ObservedObject var model: GraphicsCheck
    @AppStorage("lastAmiiboId") private var amiiboID = ""
    @AppStorage("amiiboRandomUid") private var random = false
    @State private var importing = false
    @State private var message = ""
    var body: some View {
        Form {
            Section {
                Label(model.session.amiiboSearching ? "Game is searching for a tag" : "Open the game's amiibo scan screen first", systemImage: "wave.3.right")
                if !model.session.error.isEmpty { Text(model.session.error).foregroundStyle(.red) }
                if !message.isEmpty { Text(message) }
            }
            Section("Virtual amiibo") {
                TextField("16-digit amiibo ID", text: $amiiboID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Random tag UUID", isOn: $random)
                Button("Scan amiibo ID") { SessionControl.send(5, random ? 1 : 0, amiiboID) }.disabled(!model.session.amiiboSearching || amiiboID.count != 16)
            }
            Section("Amiibo dump") {
                Text("Import your key_retail.bin in System files before using a dumped BIN. The dump's application data stays in the app.").font(.caption).foregroundStyle(.secondary)
                Button("Choose amiibo BIN") { importing = true }.disabled(!model.session.amiiboSearching)
            }
        }.navigationTitle("Amiibo")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { if case .failure(let error) = result { message = error.localizedDescription }; return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var bytes = Data(), coordination: NSError?, reading: Error?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordination) { file in
                        do { let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; guard [532,540].contains(size) else { throw CocoaError(.fileReadCorruptFile) }; bytes = try Data(contentsOf: file) } catch { reading = error }
                    }
                    if let error = coordination ?? (reading as NSError?) { throw error }
                    let folder = try AppService.root().appendingPathComponent("AmiiboImports", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let path = folder.appendingPathComponent(UUID().uuidString + ".bin"); try bytes.write(to: path, options: .atomic)
                    DispatchQueue.main.async { SessionControl.send(6, 0, path.path); message = "Amiibo scan queued." }
                } catch { DispatchQueue.main.async { message = error.localizedDescription } }
            }
        }
    }
}

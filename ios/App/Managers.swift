import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

@MainActor final class CoreManager: ObservableObject {
    @Published var response: [String: Any] = [:]
    @Published var busy = false
    @Published var error = ""
    @Published var exported: URL?
    let program: URL?
    init(program: URL? = nil) { self.program = program }
    func call(_ operation: String, _ fields: [String: Any] = [:], completion: (() -> Void)? = nil) {
        guard !busy else { return }; busy = true; error = ""
        var request = fields; request["operation"] = operation
        if let program { request["program"] = program.path }
        AppService.perform(request) { [weak self] result in
            guard let self else { return }; self.busy = false
            switch result {
            case .success(let response): self.response = response; if let path = response["export"] as? String { self.exported = URL(fileURLWithPath: path) }; completion?()
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
    func importFile(_ result: Result<[URL], Error>, operation: String, fields: [String: Any] = [:]) {
        guard !busy else { return }
        guard case .success(let urls) = result, let selection = urls.first else {
            if case .failure(let error) = result { self.error = error.localizedDescription }; return
        }
        busy = true; error = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let copied: Result<URL, Error>
            do {
                let access = selection.startAccessingSecurityScopedResource()
                defer { if access { selection.stopAccessingSecurityScopedResource() } }
                let folder = try AppService.root().appendingPathComponent("Content", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(UUID().uuidString + "." + selection.pathExtension.lowercased())
                var coordination: NSError?, copying: Error?
                NSFileCoordinator().coordinate(readingItemAt: selection, options: .withoutChanges, error: &coordination) { url in
                    do { try FileManager.default.copyItem(at: url, to: target) } catch { copying = error }
                }
                if let error = coordination ?? (copying as NSError?) { try? FileManager.default.removeItem(at: target); throw error }
                copied = .success(target)
            } catch { copied = .failure(error) }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                switch copied {
                case .failure(let error): self.error = error.localizedDescription
                case .success(let url): var request = fields; request["source"] = url.path; request["originalName"] = selection.lastPathComponent; self.call(operation, request)
                }
            }
        }
    }
    var errorView: some View { Group { if busy { ProgressView() }; if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) } } }
}

struct TitleDetails: View {
    let title: ImportedTitle
    let program: URL
    let play: () -> Void
    let launchEnabled: Bool
    @ObservedObject var library: GameLibrary
    @StateObject private var manager: CoreManager
    @State private var importing = false
    @State private var importOperation = "updates.add"
    init(title: ImportedTitle, program: URL, library: GameLibrary, launchEnabled: Bool, play: @escaping () -> Void) {
        self.title = title; self.program = program; self.library = library; self.launchEnabled = launchEnabled; self.play = play
        _manager = StateObject(wrappedValue: CoreManager(program: program))
    }
    private var information: [String: Any] { ((manager.response["metadata"] as? [String: Any])?["titles"] as? [[String: Any]])?.first ?? [:] }
    private var updates: [[String: Any]] { manager.response["updates"] as? [[String: Any]] ?? [] }
    private var dlc: [[String: Any]] { manager.response["dlc"] as? [[String: Any]] ?? [] }
    var body: some View {
        Form {
            Section {
                if let encoded = information["icon"] as? String, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 110) }
                Text(information["name"] as? String ?? title.name).font(.title2.bold())
                if let publisher = information["publisher"] as? String { Text(publisher).foregroundStyle(.secondary) }
                if let id = information["titleId"] as? String { LabeledContent("Title ID", value: id.uppercased()).font(.system(.caption, design: .monospaced)) }
                if let version = information["version"] as? String { LabeledContent("Base version", value: version) }
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: title.byteCount, countStyle: .file))
                Button("Play", action: play).buttonStyle(.borderedProminent).disabled(!launchEnabled || manager.busy)
                NavigationLink("Game settings") { SettingsEditor(program: program, name: title.name) }
                NavigationLink("Input settings") { InputSettingsView(program: program) }
                NavigationLink("Mods and cheats") { ModsView(program: program) }
                NavigationLink("Saves") { SavesView(program: program) }
                manager.errorView
                Button("Refresh title information", action: refresh)
            }
            Section("Title updates") {
                Button { manager.call("updates.select", ["path": ""]) } label: { Label("Base game only", systemImage: updates.contains(where: { $0["selected"] as? Bool == true }) ? "circle" : "checkmark.circle.fill") }
                ForEach(updates.indices, id: \.self) { index in
                    let item = updates[index], path = item["path"] as? String ?? ""
                    HStack {
                        Button { manager.call("updates.select", ["path": path]) } label: { Label(item["name"] as? String ?? "Update", systemImage: item["selected"] as? Bool == true ? "checkmark.circle.fill" : "circle") }
                        Spacer()
                        Button(role: .destructive) { manager.call("updates.remove", ["path": path]) } label: { Image(systemName: "minus.circle") }
                    }
                }
                Button("Import update NSP/XCI") { importOperation = "updates.add"; importing = true }
            }
            Section("Downloadable content") {
                ForEach(dlc.indices, id: \.self) { index in
                    let item = dlc[index], id = item["titleId"] as? String ?? "", container = item["container"] as? String ?? ""
                    Toggle(id.uppercased(), isOn: Binding(get: { item["enabled"] as? Bool ?? false }, set: { manager.call("dlc.enable", ["titleId": id, "container": container, "enabled": $0]) }))
                }
                HStack { Button("Enable all") { manager.call("dlc.enable", ["enabled": true]) }; Spacer(); Button("Disable all") { manager.call("dlc.enable", ["enabled": false]) } }
                Button("Import DLC NSP/XCI") { importOperation = "dlc.add"; importing = true }
            }
        }
        .disabled(manager.busy).navigationTitle(title.name).navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { manager.importFile($0, operation: importOperation) }
    }
    private func refresh() { manager.call("title.content") { library.metadata(title, information: information) } }
}

struct ModsView: View {
    @StateObject private var manager: CoreManager
    @State private var importing = false
    @State private var operation = "mods.import"
    @State private var removing: String?
    @State private var confirmRemove = false
    init(program: URL) { _manager = StateObject(wrappedValue: CoreManager(program: program)) }
    private var mods: [[String: Any]] { manager.response["mods"] as? [[String: Any]] ?? [] }
    private var cheats: [[String: Any]] { manager.response["cheats"] as? [[String: Any]] ?? [] }
    var body: some View {
        Form {
            Section { manager.errorView; Text("Changes apply on the next game launch. Cheats must match the executable build ID and game version.").font(.caption).foregroundStyle(.secondary) }
            Section("Mods") {
                ForEach(mods.indices, id: \.self) { index in
                    let mod = mods[index], path = mod["path"] as? String ?? ""
                    Toggle(mod["name"] as? String ?? "Mod", isOn: Binding(get: { mod["enabled"] as? Bool ?? true }, set: { manager.call("mods.enable", ["path": path, "enabled": $0]) }))
                    Button("Remove \(mod["name"] as? String ?? "mod")", role: .destructive) { removing = path; confirmRemove = true }
                }
                Button("Import mod ZIP") { operation = "mods.import"; importing = true }
            }
            Section("Cheats") {
                ForEach(cheats.indices, id: \.self) { index in
                    let cheat = cheats[index]
                    VStack(alignment: .leading) {
                        Toggle(cheat["name"] as? String ?? "Cheat", isOn: Binding(get: { cheat["enabled"] as? Bool ?? false }, set: { manager.call("cheats.enable", ["key": cheat["key"] as? String ?? "", "enabled": $0]) }))
                        Text(cheat["buildId"] as? String ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Button("Import build-ID cheat TXT") { operation = "cheats.import"; importing = true }
            }
        }
        .navigationTitle("Mods and cheats").disabled(manager.busy).task { manager.call("mods.list") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { manager.importFile($0, operation: operation) }
        .confirmationDialog("Remove this mod from the app?", isPresented: $confirmRemove, titleVisibility: .visible) { Button("Remove", role: .destructive) { if let removing { manager.call("mods.remove", ["path": removing]) } } }
    }
}

struct SavesView: View {
    @StateObject private var manager: CoreManager
    @State private var selected = ""
    @State private var restoring = false
    @State private var deleting = false
    @State private var importing = false
    init(program: URL? = nil) { _manager = StateObject(wrappedValue: CoreManager(program: program)) }
    private var saves: [[String: Any]] { manager.response["saves"] as? [[String: Any]] ?? [] }
    var body: some View {
        Form {
            Section {
                manager.errorView
                if let profile = manager.response["profile"] as? String { Text("Profile: " + profile) }
                Text("Export a backup before restoring or deleting a save. Restores accept a ZIP containing the save's files at its root. Launch a game once to create its save before importing one.").font(.caption).foregroundStyle(.secondary)
                if let exported = manager.exported { ShareLink(item: exported) { Label("Share save backup", systemImage: "square.and.arrow.up") } }
            }
            ForEach(saves.indices, id: \.self) { index in
                let save = saves[index], id = save["id"] as? String ?? ""
                Section(save["titleId"] as? String ?? "Save") {
                    LabeledContent("Type", value: save["type"] as? String ?? "")
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: (save["size"] as? NSNumber)?.int64Value ?? 0, countStyle: .file))
                    Button("Export backup") { manager.call("saves.export", ["id": id]) }
                    Button("Restore ZIP backup") { selected = id; restoring = true }
                    Button("Delete save", role: .destructive) { selected = id; deleting = true }
                }
            }
            if saves.isEmpty && !manager.busy { Section { Text("No saves for the selected profile and title.").foregroundStyle(.secondary) } }
        }
        .navigationTitle("Saves").disabled(manager.busy).task { manager.call("saves.list") }
        .confirmationDialog("Replace this save with a ZIP backup?", isPresented: $restoring, titleVisibility: .visible) { Button("Choose backup", role: .destructive) { importing = true } }
        .confirmationDialog("Permanently delete this save?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { manager.call("saves.delete", ["id": selected, "confirmed": true]) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { manager.importFile($0, operation: "saves.restore", fields: ["id": selected]) }
    }
}

struct ProfilesView: View {
    @StateObject private var manager = CoreManager()
    @State private var editingId: String?
    @State private var editingName = ""
    @State private var editing = false
    @State private var deleting: String?
    @State private var confirmDelete = false
    @State private var photo: PhotosPickerItem?
    @State private var avatarId = ""
    private var profiles: [[String: Any]] { manager.response["profiles"] as? [[String: Any]] ?? [] }
    var body: some View {
        Form {
            Section { manager.errorView; Text("The selected profile is used for games and saves.").font(.caption).foregroundStyle(.secondary) }
            ForEach(profiles.indices, id: \.self) { index in
                let profile = profiles[index], id = profile["id"] as? String ?? ""
                Section {
                    HStack {
                        if let base64 = profile["image"] as? String, let data = Data(base64Encoded: base64), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 50, height: 50).clipShape(Circle()) }
                        Button { manager.call("profiles.select", ["id": id]) } label: { Label(profile["name"] as? String ?? id, systemImage: profile["selected"] as? Bool == true ? "checkmark.circle.fill" : "circle") }
                    }
                    Button("Rename") { editingId = id; editingName = profile["name"] as? String ?? ""; editing = true }
                    PhotosPicker(selection: Binding(get: { avatarId == id ? photo : nil }, set: { avatarId = id; photo = $0 }), matching: .images) { Text("Choose avatar") }
                    if id != "00000000000000010000000000000000" { Button("Delete profile and its saves", role: .destructive) { deleting = id; confirmDelete = true } }
                }
            }
            Section { Button("Add profile") { editingId = nil; editingName = ""; editing = true }.disabled(profiles.count >= 8) }
        }
        .navigationTitle("Profiles").disabled(manager.busy).task { manager.call("profiles.list") }
        .alert(editingId == nil ? "New profile" : "Rename profile", isPresented: $editing) {
            TextField("Name", text: $editingName)
            Button("Save") { var fields: [String: Any] = ["name": editingName]; if let editingId { fields["id"] = editingId }; manager.call(editingId == nil ? "profiles.add" : "profiles.rename", fields) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this profile and all its saves?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if let deleting { manager.call("profiles.delete", ["id": deleting, "confirmed": true]) } } }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            let id = avatarId
            Task {
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
                        UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256)); image.draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
                    }
                    guard let jpeg = thumbnail.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileReadCorruptFile) }
                    manager.call("profiles.image", ["id": id, "image": jpeg.base64EncodedString()])
                } catch { manager.error = error.localizedDescription }
                photo = nil
            }
        }
    }
}

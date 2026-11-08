import Foundation
import SwiftUI

@MainActor final class AppActivity: ObservableObject {
    static let shared = AppActivity()
    @Published var pending = 0
}

enum AppService {
    static func root() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var root = support.appendingPathComponent("RyuCore", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try root.setResourceValues(flags)
        return root
    }
    static func perform(_ request: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        DispatchQueue.main.async { AppActivity.shared.pending += 1 }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[String: Any], Error>
            do {
                let root = try root()
                let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                var report = [CChar](repeating: 0, count: 1024 * 1024)
                let code = root.path.withCString { directory in json.withCString { payload in
                    report.withUnsafeMutableBufferPointer { ryu_app(directory, payload, $0.baseAddress, $0.count) }
                } }
                let text = report.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                guard let response = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
                if code != 0 { throw NSError(domain: "Ryu", code: Int(code), userInfo: [NSLocalizedDescriptionKey: response["error"] as? String ?? "The operation failed."]) }
                result = .success(response)
            } catch { result = .failure(error) }
            DispatchQueue.main.async { AppActivity.shared.pending -= 1; completion(result) }
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var schema: [SettingField] = []
    @Published var values: [String: Any] = [:]
    @Published var overridden: Set<String> = []
    @Published var busy = false
    @Published var error = ""
    let program: URL?
    init(program: URL? = nil) { self.program = program }
    func load() { call("settings.get") }
    func save(_ key: String, _ value: Any) { call("settings.save", changes: [key: value]) }
    func reset() { call("settings.reset") }
    private func call(_ operation: String, changes: [String: Any] = [:]) {
        guard !busy else { return }; busy = true; error = ""
        var request: [String: Any] = ["operation": operation, "changes": changes]
        if let program { request["program"] = program.path }
        AppService.perform(request) { [weak self] result in
            guard let self else { return }; self.busy = false
            switch result {
            case .failure(let error): self.error = error.localizedDescription
            case .success(let response):
                do {
                    self.schema = try JSONDecoder().decode([SettingField].self, from: JSONSerialization.data(withJSONObject: response["schema"] ?? []))
                    self.values = response["values"] as? [String: Any] ?? [:]
                    self.overridden = Set((response["overrides"] as? [String: Any] ?? [:]).keys)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct SettingField: Decodable, Identifiable {
    var id: String { key }
    let key, title, section, description, kind: String
    let choices: [String]?
    let minimum, maximum: Double?
    let integer: Bool
}

struct SettingsEditor: View {
    @StateObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var confirmingReset = false
    let name: String
    init(program: URL? = nil, name: String = "Global settings") {
        _store = StateObject(wrappedValue: SettingsStore(program: program)); self.name = name
    }
    private var sections: [String] { ["Graphics", "System", "CPU", "Audio", "Network", "Debug", "Logging", "Interface", "Input"] }
    var body: some View {
        Form {
            Section {
                Text(store.program == nil ? "Applies to games without an override. Changes take effect on the next launch." : "Overrides global settings for this game. Changes take effect on the next launch.").font(.caption).foregroundStyle(.secondary)
                if store.busy { ProgressView() }
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.red).textSelection(.enabled) }
            }
            ForEach(sections, id: \.self) { section in
                let fields = store.schema.filter { $0.section == section && (search.isEmpty || ($0.title + " " + $0.description).localizedCaseInsensitiveContains(search)) }
                if !fields.isEmpty {
                    Section(section) { ForEach(fields) { field in SettingRow(field: field, store: store) } }
                }
            }
            Section {
                Button(store.program == nil ? "Restore defaults" : "Use global settings", role: .destructive) { confirmingReset = true }
            }
            Section("iOS platform") {
                LabeledContent("Graphics API", value: "Vulkan / MoltenVK / Metal")
                LabeledContent("Memory manager", value: "Software page tables")
                LabeledContent("CPU", value: "ARM64 JIT via StikDebug")
                Text("Desktop OpenGL, hypervisor execution and Discord RPC are unavailable in the iOS sandbox.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(store.busy).searchable(text: $search)
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .task { store.load() }
        .confirmationDialog("Reset these settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive, action: store.reset)
        }
    }
}

private struct SettingRow: View {
    let field: SettingField
    @ObservedObject var store: SettingsStore
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if field.kind == "bool" {
                Toggle(field.title, isOn: Binding(get: { store.values[field.key] as? Bool ?? false }, set: { store.save(field.key, $0) }))
            } else if let choices = field.choices {
                Picker(field.title, selection: Binding(get: { store.values[field.key] as? String ?? "" }, set: { store.save(field.key, $0) })) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
            } else {
                HStack {
                    Text(field.title)
                    Spacer()
                    TextField("Value", text: $draft).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(commit)
                    Button("Save", action: commit).font(.caption)
                }
            }
            if !field.description.isEmpty { Text(field.description).font(.caption).foregroundStyle(.secondary) }
            if store.program != nil && store.overridden.contains(field.key) { Text("Game override").font(.caption2).foregroundStyle(.teal) }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.busy) { _, busy in if !busy { refresh() } }
    }
    private func refresh() { draft = store.values[field.key].map { String(describing: $0) } ?? "" }
    private func commit() {
        if field.kind == "number" {
            guard let number = Double(draft), number.isFinite else { store.error = "Enter a valid number for \(field.title)."; return }
            store.save(field.key, number)
        } else { store.save(field.key, draft) }
    }
}

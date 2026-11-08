import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SystemFiles: ObservableObject {
    @Published var isBusy = false
    @Published var status = "Reading system files…"
    @Published var message = ""
    init() { refresh() }
    private nonisolated static func directory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var root = support.appendingPathComponent("RyuCore", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        return root
    }
    func refresh() { perform(action: 0, selection: nil) }
    func imported(_ result: Result<[URL], Error>, firmware: Bool) {
        switch result {
        case .failure(let error): message = error.localizedDescription
        case .success(let urls): if let url = urls.first { perform(action: firmware ? 2 : 1, selection: url) }
        }
    }
    private func perform(action: Int32, selection: URL?) {
        guard !isBusy else { return }
        isBusy = true
        if action != 0 { message = action == 1 ? "Importing keys…" : "Copying, verifying and installing firmware…" }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var output = [CChar](repeating: 0, count: 4096)
            var code: Int32 = -1
            var text = ""
            var staging: URL?
            do {
                let root = try Self.directory()
                var source: URL?
                if let selection {
                    let access = selection.startAccessingSecurityScopedResource()
                    defer { if access { selection.stopAccessingSecurityScopedResource() } }
                    let name = selection.lastPathComponent
                    if action == 1 && !["prod.keys", "title.keys", "key_retail.bin"].contains(name) { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Select prod.keys, title.keys or key_retail.bin with its original filename."]) }
                    let ext = selection.pathExtension.lowercased()
                    if action == 2 && !["zip", "xci"].contains(ext) { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Select a firmware ZIP or an XCI containing firmware."]) }
                    let temporary = root.appendingPathComponent("import-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
                    staging = temporary
                    let copy = temporary.appendingPathComponent(action == 1 ? name : "firmware." + ext)
                    var coordination: NSError?, copying: Error?
                    NSFileCoordinator().coordinate(readingItemAt: selection, options: .withoutChanges, error: &coordination) { url in
                        do { try FileManager.default.copyItem(at: url, to: copy) } catch { copying = error }
                    }
                    if let error = coordination { throw error }; if let error = copying { throw error }
                    source = copy
                }
                code = root.path.withCString { directory in
                    output.withUnsafeMutableBufferPointer { buffer in
                        if let source { return source.path.withCString { path in ryu_content(action, path, directory, buffer.baseAddress, buffer.count) } }
                        return ryu_content(action, nil, directory, buffer.baseAddress, buffer.count)
                    }
                }
                text = output.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if action == 1 && code == 0, let selection {
                    let imported = root.appendingPathComponent("system/" + selection.lastPathComponent)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: imported.path)
                }
            } catch { text = "Could not import system files: \(error.localizedDescription)" }
            if let staging { try? FileManager.default.removeItem(at: staging) }
            let resultCode = code, resultText = text
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if action == 0 { self.status = resultText }
                else { self.message = resultText; if resultCode == 0 { self.refresh() } }
            }
        }
    }
}

struct SystemFilesPanel: View {
    @ObservedObject var system: SystemFiles
    let blocked: Bool
    @State private var showingPicker = false
    @State private var firmware = false
    var body: some View {
        GroupBox("System files") {
            VStack(alignment: .leading, spacing: 12) {
                Text(system.status).font(.callout)
                Text("Import your prod.keys first, then install your firmware ZIP. These files stay in this app.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Import keys") { firmware = false; showingPicker = true }
                    Button("Install firmware") { firmware = true; showingPicker = true }
                }.buttonStyle(.bordered).disabled(blocked || system.isBusy)
                if system.isBusy { ProgressView() }
                if !system.message.isEmpty { Text(system.message).font(.caption).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in system.imported(result, firmware: firmware) }
    }
}

import Combine
import Foundation

struct ImportedTitle: Codable, Identifiable {
    let id: UUID
    var name: String
    let storedFilename: String
    let byteCount: Int64
    let importedAt: Date
    var favorite: Bool? = nil
    var lastPlayedAt: Date? = nil
    var secondsPlayed: Double? = nil
    var titleID: String? = nil
    var publisher: String? = nil
    var displayVersion: String? = nil
    var icon: String? = nil
}

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var titles: [ImportedTitle] = []
    @Published var isImporting = false
    @Published var message = ""
    private var playing: (UUID, Date)?

    func toggleFavorite(_ title: ImportedTitle) { change(title.id) { $0.favorite = !($0.favorite ?? false) } }
    func rename(_ title: ImportedTitle, to name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }; change(title.id) { $0.name = value }
    }
    func metadata(_ title: ImportedTitle, information: [String: Any]) {
        change(title.id) {
            if let name = information["name"] as? String, !name.isEmpty { $0.name = name }
            $0.titleID = information["titleId"] as? String; $0.publisher = information["publisher"] as? String
            $0.displayVersion = information["version"] as? String; $0.icon = information["icon"] as? String
        }
    }
    func beginPlaying(_ title: ImportedTitle) {
        playing = (title.id, Date()); change(title.id) { $0.lastPlayedAt = Date() }
    }
    func endPlaying() {
        guard let (id, began) = playing else { return }; playing = nil
        change(id) { $0.secondsPlayed = ($0.secondsPlayed ?? 0) + max(0, Date().timeIntervalSince(began)) }
    }
    private func change(_ id: UUID, mutate: (inout ImportedTitle) -> Void) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        var updated = titles; mutate(&updated[index])
        do { try Self.save(updated); titles = updated } catch { message = error.localizedDescription }
    }
    func remove(_ title: ImportedTitle) {
        guard let source = executableURL(for: title) else { return }
        do {
            let trash = try Self.directory().appendingPathComponent("remove-" + UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: trash)
            do { let updated = titles.filter { $0.id != title.id }; try Self.save(updated); titles = updated }
            catch { try? FileManager.default.moveItem(at: trash, to: source); throw error }
            try FileManager.default.removeItem(at: trash)
            message = "Removed \(title.name). Its saves, settings and imported add-on content are retained."
        } catch { message = error.localizedDescription }
    }

    init() {
        do { titles = try Self.readIndex() }
        catch { message = "Could not read the game library: \(error.localizedDescription)" }
    }

    func executableURL(for title: ImportedTitle) -> URL? {
        guard ["nro", "nso", "nsp", "xci"].contains(URL(fileURLWithPath: title.storedFilename).pathExtension.lowercased()),
              URL(fileURLWithPath: title.storedFilename).lastPathComponent == title.storedFilename else { return nil }
        return try? Self.directory().appendingPathComponent(title.storedFilename)
    }

    private nonisolated static func directory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        var root = support.appendingPathComponent("RyuLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root
    }

    private nonisolated static func readIndex() throws -> [ImportedTitle] {
        let index = try directory().appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([ImportedTitle].self, from: Data(contentsOf: index))
    }

    private nonisolated static func save(_ titles: [ImportedTitle]) throws {
        let data = try JSONEncoder().encode(titles)
        try data.write(to: directory().appendingPathComponent("library.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func importSelection(_ result: Result<[URL], Error>) {
        guard !isImporting else { return }
        switch result {
        case .failure(let error): message = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImporting = true
            message = "Copying selected files into the app…"
            let existing = titles
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var updated = existing
                var failures: [String] = []
                for source in urls {
                    let accessed = source.startAccessingSecurityScopedResource()
                    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                    var destination: URL?
                    do {
                        let ext = source.pathExtension.lowercased()
                        guard ["nro", "nso", "nsp", "xci"].contains(ext) else {
                            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "Select an NRO, NSO, NSP or XCI file."])
                        }
                        let id = UUID()
                        let filename = "\(id.uuidString).\(ext)"
                        let target = try Self.directory().appendingPathComponent(filename)
                        destination = target
                        let coordinator = NSFileCoordinator()
                        var coordinationError: NSError?
                        var copyError: Error?
                        coordinator.coordinate(readingItemAt: source, options: .withoutChanges,
                            error: &coordinationError) { coordinated in
                            do { try FileManager.default.copyItem(at: coordinated, to: target) }
                            catch { copyError = error }
                        }
                        if let error = coordinationError { throw error }
                        if let error = copyError { throw error }
                        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
                        guard attributes[.type] as? FileAttributeType == .typeRegular,
                              let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        let input = try FileHandle(forReadingFrom: target)
                        let header = try input.read(upToCount: 0x104) ?? Data()
                        try input.close()
                        let offset = ext == "nro" ? 0x10 : ext == "xci" ? 0x100 : 0
                        let magic = ext == "nro" ? "NRO0" : ext == "nso" ? "NSO0" : ext == "nsp" ? "PFS0" : "HEAD"
                        guard header.count >= offset + 4, header.subdata(in: offset..<(offset + 4)) == Data(magic.utf8) else {
                            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The file header does not match its format."])
                        }
                        let item = ImportedTitle(id: id, name: source.deletingPathExtension().lastPathComponent,
                            storedFilename: filename, byteCount: size.int64Value, importedAt: Date())
                        let next = updated + [item]
                        try Self.save(next)
                        updated = next
                        destination = nil
                    } catch {
                        if let destination { try? FileManager.default.removeItem(at: destination) }
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                let completed = updated
                let added = updated.count - existing.count
                let text = "Imported \(added) title(s)." + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
                Task { @MainActor in
                    self?.titles = completed
                    self?.message = text
                    self?.isImporting = false
                }
            }
        }
    }
}

import SwiftUI

struct LibraryPanel: View {
    @ObservedObject var library: GameLibrary
    let blocked, jitReady: Bool
    let importGames: () -> Void
    let play: (ImportedTitle, URL) -> Void
    @State private var search = ""
    @AppStorage("GameListViewMode") private var viewMode = 0
    @AppStorage("ApplicationSort") private var sort = 0
    @AppStorage("IsAscendingOrder") private var ascending = true
    @AppStorage("GridSize") private var gridSize = 2
    @AppStorage("ShowNames") private var showNames = true
    @State private var favoritesOnly = false
    @State private var format = "All"
    @State private var selected: ImportedTitle?
    @State private var confirmingRemove = false
    @State private var renaming = false
    @State private var renamed = ""
    private var filtered: [ImportedTitle] {
        library.titles.filter { title in
            (!favoritesOnly || title.favorite == true) && (format == "All" || URL(fileURLWithPath: title.storedFilename).pathExtension.uppercased() == format) &&
            (search.isEmpty || (title.name + " " + (title.titleID ?? "") + " " + (title.publisher ?? "")).localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            func less(_ lhs: ImportedTitle, _ rhs: ImportedTitle) -> Bool {
                switch sort {
                case 1: return lhs.importedAt < rhs.importedAt
                case 2: return (lhs.lastPlayedAt ?? .distantPast) < (rhs.lastPlayedAt ?? .distantPast)
                case 3: return lhs.byteCount < rhs.byteCount
                case 4: return (lhs.secondsPlayed ?? 0) < (rhs.secondsPlayed ?? 0)
                default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
            return ascending ? less(a, b) : less(b, a)
        }
    }
    var body: some View {
        GroupBox("Library") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Search games, publishers or title IDs", text: $search).textFieldStyle(.roundedBorder)
                HStack {
                    Menu("View and sort", systemImage: "line.3.horizontal.decrease") {
                        Picker("View", selection: $viewMode) { Text("List").tag(0); Text("Grid").tag(1) }
                        Picker("Sort", selection: $sort) { Text("Name").tag(0); Text("Imported").tag(1); Text("Last played").tag(2); Text("Size").tag(3); Text("Time played").tag(4) }
                        Toggle("Ascending", isOn: $ascending); Toggle("Show names", isOn: $showNames)
                        Picker("Icon size", selection: $gridSize) { Text("Small").tag(1); Text("Medium").tag(2); Text("Large").tag(3) }
                        Picker("Format", selection: $format) { ForEach(["All", "XCI", "NSP", "NRO", "NSO"], id: \.self) { Text($0).tag($0) } }
                    }
                    Spacer()
                    Toggle("Favorites", isOn: $favoritesOnly).toggleStyle(.button).labelStyle(.titleOnly)
                }
                if filtered.isEmpty { Text(library.titles.isEmpty ? "Import a game to get started." : "No matching games.").foregroundStyle(.secondary) }
                if viewMode == 1 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(gridSize * 45 + 40)))], spacing: 16) {
                        ForEach(filtered) { title in card(title, grid: true) }
                    }
                } else { ForEach(filtered) { title in card(title, grid: false) } }
                if !library.message.isEmpty { Text(library.message).font(.callout).textSelection(.enabled) }
                if library.isImporting { ProgressView() }
                Button("Import game or homebrew", action: importGames).buttonStyle(.bordered).disabled(blocked)
                Text("Open a game's details to manage its settings, updates, DLC, mods, cheats and saves. Base NSP/XCI games need your keys and firmware.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Remove this imported game? Saves and add-ons will be retained.", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove game", role: .destructive) { if let selected { library.remove(selected) } }
        }
        .alert("Rename library entry", isPresented: $renaming) {
            TextField("Name", text: $renamed); Button("Save") { if let selected { library.rename(selected, to: renamed) } }; Button("Cancel", role: .cancel) {}
        }
    }
    @ViewBuilder private func icon(_ title: ImportedTitle, size: CGFloat) -> some View {
        if let encoded = title.icon, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 10)) }
        else { Image(systemName: "gamecontroller.fill").resizable().scaledToFit().padding(size / 5).frame(width: size, height: size).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)) }
    }
    @ViewBuilder private func card(_ title: ImportedTitle, grid: Bool) -> some View {
        if let executable = library.executableURL(for: title) {
            Group {
                if grid {
                    VStack {
                        NavigationLink { details(title, executable) } label: { icon(title, size: CGFloat(gridSize * 40 + 40)) }
                        if showNames { Text(title.name).font(.caption).lineLimit(2) }
                        Button("Play") { play(title, executable) }.disabled(!jitReady || blocked)
                    }
                } else {
                    HStack {
                        NavigationLink { details(title, executable) } label: { icon(title, size: 54) }
                        VStack(alignment: .leading, spacing: 3) {
                            NavigationLink(title.name) { details(title, executable) }
                            Text([title.displayVersion, ByteCountFormatter.string(fromByteCount: title.byteCount, countStyle: .file)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            if let date = title.lastPlayedAt { Text("Last played " + date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if title.favorite == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        Button("Play") { play(title, executable) }.disabled(!jitReady || blocked)
                    }
                }
            }
            .contextMenu {
                Button(title.favorite == true ? "Remove favorite" : "Favorite", systemImage: "star") { library.toggleFavorite(title) }
                Button("Rename", systemImage: "pencil") { selected = title; renamed = title.name; renaming = true }
                Button("Remove game", systemImage: "trash", role: .destructive) { selected = title; confirmingRemove = true }.disabled(blocked)
            }
        }
    }
    private func details(_ title: ImportedTitle, _ executable: URL) -> some View {
        TitleDetails(title: title, program: executable, library: library, launchEnabled: jitReady && !blocked) { play(title, executable) }
    }
}

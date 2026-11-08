import Foundation
import SwiftUI
import GameController
import CryptoKit

struct ControllerProfile: Codable, Identifiable {
    var id = UUID()
    var name = "Controller"
    var type: Int32 = 1
    var device = 0
    var deadzone: Float = 0.1
    var range: Float = 1
    var invertLeftX = false, invertLeftY = false, invertRightX = false, invertRightY = false
    var swapSticks = false
    var keyboard = false
    var motion = "controller"
    var motionSensitivity: Float = 100
    var motionDeadzone: Float = 0.01
    var rumble = true
    var rumbleStrength: Float = 1
    var mapping: [String: String] = ["0":"B", "1":"A", "2":"Y", "3":"X", "4":"LS", "5":"RS", "6":"L", "7":"R", "8":"ZL", "9":"ZR", "10":"Plus", "11":"Minus", "12":"Left", "13":"Up", "14":"Right", "15":"Down"]
    var keyboardMapping: [String: Int] = ["0":29, "1":27, "2":6, "3":25, "4":9, "5":11, "6":8, "7":24, "8":20, "9":18, "10":46, "11":45, "12":80, "13":82, "14":79, "15":81]
}
struct InputConfiguration: Codable {
    var profiles: [ControllerProfile]
    var assignments: [UUID?]
    var allowDuplicateDeviceAssignment = false
    var hideTouchWithController = true
    var touchOpacity = 0.7
    var touchScale = 1.0
    var pollRate = 120.0
    static func defaults() -> InputConfiguration {
        let profiles = (0..<8).map { i -> ControllerProfile in var p = ControllerProfile(); p.name = "Player \(i + 1)"; p.device = i; p.keyboard = i == 0; return p }
        return InputConfiguration(profiles: profiles, assignments: profiles.enumerated().map { $0.offset == 0 ? $0.element.id : nil })
    }
}

@MainActor final class InputSettingsStore: ObservableObject {
    @Published var configuration = InputConfiguration.defaults()
    @Published var error = ""
    @Published var custom = false
    let program: URL?
    init(program: URL? = nil) { self.program = program; load() }
    private static func location(_ program: URL?) throws -> URL {
        let root = try AppService.root().appendingPathComponent("controllers", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = program.map { SHA256.hash(data: Data($0.path.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "global"
        return root.appendingPathComponent(name + ".json")
    }
    static func effective(_ program: URL?) throws -> InputConfiguration {
        let path = try location(program)
        let global = try location(nil)
        let selected = FileManager.default.fileExists(atPath: path.path) ? path : global
        guard FileManager.default.fileExists(atPath: selected.path) else { return .defaults() }
        let config = try JSONDecoder().decode(InputConfiguration.self, from: Data(contentsOf: selected))
        guard config.assignments.count == 8, config.profiles.count <= 64, config.pollRate >= 30, config.pollRate <= 240, config.touchOpacity >= 0, config.touchOpacity <= 1, config.touchScale >= 0.5, config.touchScale <= 1.5 else { throw CocoaError(.fileReadCorruptFile) }
        return config
    }
    func load() {
        do { configuration = try Self.effective(program); custom = try program != nil && FileManager.default.fileExists(atPath: Self.location(program).path) }
        catch { self.error = error.localizedDescription }
    }
    func save() {
        do { try JSONEncoder().encode(configuration).write(to: Self.location(program), options: .atomic); custom = program != nil; error = "" }
        catch { self.error = error.localizedDescription }
    }
    func reset() {
        do { let path = try Self.location(program); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }; load() }
        catch { self.error = error.localizedDescription }
    }
    func addProfile() { guard configuration.profiles.count < 64 else { return }; var p = ControllerProfile(); p.name = "Profile \(configuration.profiles.count + 1)"; configuration.profiles.append(p); save() }
}

struct InputSettingsView: View {
    @StateObject private var store: InputSettingsStore
    init(program: URL? = nil) { _store = StateObject(wrappedValue: InputSettingsStore(program: program)) }
    var body: some View {
        Form {
            Section {
                Text("Changes apply at the next launch. Each player can use a saved controller profile. Button names in profiles refer to Apple's controller labels; the default mapping uses Switch button positions.").font(.caption).foregroundStyle(.secondary)
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.red) }
                if store.program != nil { Text(store.custom ? "Custom input configuration" : "Using global input configuration"); Button("Use global input settings", action: store.reset) }
            }
            Section("Players") {
                ForEach(0..<8, id: \.self) { player in
                    Picker("Player \(player + 1)", selection: Binding(get: { store.configuration.assignments[player] }, set: { store.configuration.assignments[player] = $0; store.save() })) {
                        Text("Disconnected").tag(Optional<UUID>.none)
                        ForEach(store.configuration.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Toggle("Allow duplicate device assignment", isOn: $store.configuration.allowDuplicateDeviceAssignment)
            }
            Section("Profiles") {
                ForEach(store.configuration.profiles.indices, id: \.self) { index in NavigationLink(store.configuration.profiles[index].name) { ControllerProfileEditor(store: store, index: index) } }
                Button("Add profile", action: store.addProfile)
            }
            Section("Touch controls") {
                Toggle("Hide controls when a controller is connected", isOn: $store.configuration.hideTouchWithController)
                LabeledContent("Opacity", value: store.configuration.touchOpacity.formatted(.percent))
                Slider(value: $store.configuration.touchOpacity, in: 0.1...1)
                LabeledContent("Size", value: store.configuration.touchScale.formatted(.percent))
                Slider(value: $store.configuration.touchScale, in: 0.5...1.5)
            }
            Section("Polling") { Picker("Input polling", selection: $store.configuration.pollRate) { Text("60 Hz").tag(60.0); Text("120 Hz").tag(120.0); Text("240 Hz").tag(240.0) } }
            Section("Connected controllers") {
                let controllers = GCController.controllers()
                if controllers.isEmpty { Text("None connected").foregroundStyle(.secondary) }
                ForEach(controllers.indices, id: \.self) { index in Text("\(index + 1): \(controllers[index].vendorName ?? "Controller")") }
                Button("Search for controllers") { GCController.startWirelessControllerDiscovery(completionHandler: nil) }
            }
        }
        .navigationTitle("Input settings")
        .onChange(of: store.configuration) { _, _ in store.save() }
    }
}

private struct ControllerProfileEditor: View {
    @ObservedObject var store: InputSettingsStore
    let index: Int
    private var profile: Binding<ControllerProfile> { $store.configuration.profiles[index] }
    private let buttonNames = ["A", "B", "X", "Y", "Left stick", "Right stick", "L", "R", "ZL", "ZR", "+", "−", "D-pad left", "D-pad up", "D-pad right", "D-pad down"]
    private let sources = ["Unbound", "A", "B", "X", "Y", "LS", "RS", "L", "R", "ZL", "ZR", "Plus", "Minus", "Left", "Up", "Right", "Down"]
    var body: some View {
        Form {
            Section {
                TextField("Profile name", text: profile.name)
                Picker("Emulated controller", selection: profile.type) { Text("Pro Controller").tag(Int32(1)); Text("Handheld (player 1)").tag(Int32(2)); Text("Joy-Con pair").tag(Int32(4)); Text("Left Joy-Con").tag(Int32(8)); Text("Right Joy-Con").tag(Int32(16)) }
                Stepper("Physical controller: \(store.configuration.profiles[index].device + 1)", value: profile.device, in: 0...7)
                Toggle("Keyboard controls", isOn: profile.keyboard)
            }
            Section("Sticks") {
                LabeledContent("Deadzone", value: Double(store.configuration.profiles[index].deadzone).formatted(.percent)); Slider(value: profile.deadzone, in: 0...0.9)
                LabeledContent("Range", value: Double(store.configuration.profiles[index].range).formatted(.percent)); Slider(value: profile.range, in: 0.1...2)
                Toggle("Swap sticks", isOn: profile.swapSticks)
                Toggle("Invert left X", isOn: profile.invertLeftX); Toggle("Invert left Y", isOn: profile.invertLeftY)
                Toggle("Invert right X", isOn: profile.invertRightX); Toggle("Invert right Y", isOn: profile.invertRightY)
            }
            Section("Buttons") {
                ForEach(0..<16, id: \.self) { bit in
                    Picker(buttonNames[bit], selection: Binding(get: { store.configuration.profiles[index].mapping[String(bit)] ?? "Unbound" }, set: { store.configuration.profiles[index].mapping[String(bit)] = $0 })) { ForEach(sources, id: \.self) { Text($0).tag($0) } }
                }
            }
            Section("Keyboard mapping") {
                Text("USB HID key codes: A=4, Z=29, Return=40, arrows=79–82. WASD and IJKL drive the two sticks.").font(.caption)
                ForEach(0..<16, id: \.self) { bit in
                    Stepper("\(buttonNames[bit]): \(store.configuration.profiles[index].keyboardMapping[String(bit)] ?? 0)", value: Binding(get: { store.configuration.profiles[index].keyboardMapping[String(bit)] ?? 0 }, set: { store.configuration.profiles[index].keyboardMapping[String(bit)] = $0 }), in: 0...255)
                }
            }
            Section("Motion") {
                Picker("Source", selection: profile.motion) { Text("Off").tag("off"); Text("Controller").tag("controller"); Text("iPhone / iPad").tag("device") }
                LabeledContent("Sensitivity", value: String(format: "%.0f%%", store.configuration.profiles[index].motionSensitivity)); Slider(value: profile.motionSensitivity, in: 1...300)
                LabeledContent("Gyro deadzone", value: String(format: "%.3f rad/s", store.configuration.profiles[index].motionDeadzone)); Slider(value: profile.motionDeadzone, in: 0...0.5)
            }
            Section("Rumble") {
                Toggle("Enable rumble", isOn: profile.rumble)
                Slider(value: profile.rumbleStrength, in: 0...2)
                Text("Uses Core Haptics on supported controllers or the iPhone. Switch HD rumble frequencies are approximated by the available hardware.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(store.configuration.profiles[index].name).onDisappear { store.save() }
    }
}

extension ControllerProfile: Equatable {}
extension InputConfiguration: Equatable {}

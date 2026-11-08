import Combine
import Foundation
import Metal
import QuartzCore
import SwiftUI
import UIKit
import AVFAudio

struct GameApplet: Decodable {
    let id: Int32
    let kind: Int
    let title: String
    let message: String
    let initial: String
    let maximum: Int
    let minimum: Int
}

@MainActor
final class GraphicsCheck: ObservableObject {
    @Published var isRunning = false
    @Published var report = ""
    @Published var passed = false
    @Published var needsRestart = false
    @Published var frames: UInt64 = 0
    @Published var audioFrames: UInt64 = 0
    @Published var fps = 0
    @Published var applet: GameApplet?
    @Published var appletText = ""
    let isGuest: Bool
    var programURL: URL?
    var displayTitle = "Ryu Catch"

    init(isGuest: Bool = false) {
        self.isGuest = isGuest
        if let saved = Self.savedTrace(guest: isGuest) { report = "Previous run:\n" + saved }
    }

    nonisolated private static func savedTrace(guest: Bool = false) -> String? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: support.appendingPathComponent("RyuCore/" + (guest ? "guest-last-run.log" : "graphics-last-run.log"))) else { return nil }
        return String(decoding: data.suffix(48 * 1024), as: UTF8.self)
    }

    func run(layer: CAMetalLayer) {
        guard !isRunning, !needsRestart, layer.drawableSize.width > 0, layer.drawableSize.height > 0 else { return }
        ryu_graphics_prepare()
        if isGuest {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setPreferredSampleRate(48_000)
                try session.setPreferredIOBufferDuration(0.01)
                try session.setActive(true)
                UIApplication.shared.isIdleTimerDisabled = true
            } catch { report = "Could not start game audio: \(error.localizedDescription)"; return }
        }
        isRunning = true
        passed = false
        frames = 0
        audioFrames = 0
        let audioStart = ryu_audio_frames()
        report = isGuest ? "Booting homebrew with the real CPU and GPU…" : "Initializing the upstream Vulkan renderer…"
        let guest = isGuest
        let program = programURL ?? (guest ? Bundle.main.url(forResource: "deko_basic", withExtension: "nro") : nil)
        if guest {
            Task { [weak self] in
                var previousFrames: UInt64 = 0
                var previousTime = ProcessInfo.processInfo.systemUptime
                while self?.isRunning == true {
                    let count = ryu_homebrew_frames()
                    let now = ProcessInfo.processInfo.systemUptime
                    self?.frames = count
                    self?.fps = Int(Double(count >= previousFrames ? count - previousFrames : 0) / max(0.01, now - previousTime))
                    previousFrames = count; previousTime = now
                    self?.audioFrames = ryu_audio_frames() &- audioStart
                    self?.pollApplet()
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        let width = Int32(layer.drawableSize.width)
        let height = Int32(layer.drawableSize.height)
        // The closure owns the layer until the native worker has joined.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, layer] in
            var status: Int32 = -1
            var message: String
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                var directory = support.appendingPathComponent("RyuCore", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                guard let frameworks = Bundle.main.privateFrameworksPath else { throw CocoaError(.fileNoSuchFile) }
                let library = frameworks + "/MoltenVK.framework/MoltenVK"
                if guest && program == nil { throw CocoaError(.fileNoSuchFile) }
                var output = [CChar](repeating: 0, count: 4096)
                status = library.withCString { lib in
                    directory.path.withCString { path in
                        output.withUnsafeMutableBufferPointer { buffer in
                            if guest, let program {
                                return program.path.withCString { executable in
                                    ryu_homebrew_run(lib, Unmanaged.passUnretained(layer).toOpaque(), width, height,
                                        executable, path, buffer.baseAddress, buffer.count)
                                }
                            }
                            return ryu_graphics_check(lib, Unmanaged.passUnretained(layer).toOpaque(), width, height,
                                path, buffer.baseAddress, buffer.count)
                        }
                    }
                }
                message = output.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if let saved = Self.savedTrace(guest: guest) { message += "\n\nSaved run trace:\n" + saved }
            } catch { message = "Could not initialize renderer storage: \(error.localizedDescription)" }
            let completedStatus = status
            let completedMessage = message
            Task { @MainActor in
                self?.isRunning = false
                self?.passed = completedStatus == 0
                self?.needsRestart = completedStatus < 0
                self?.report = completedMessage
                self?.applet = nil
                if guest {
                    UIApplication.shared.isIdleTimerDisabled = false
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }
    }

    func cancel() { ryu_graphics_cancel() }
    private func pollApplet() {
        var bytes = [CChar](repeating: 0, count: 32768)
        bytes.withUnsafeMutableBufferPointer { ryu_ui_poll($0.baseAddress, $0.count) }
        let text = bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        if let data = text.data(using: .utf8), let prompt = try? JSONDecoder().decode(GameApplet.self, from: data), prompt.id != applet?.id {
            appletText = prompt.initial; applet = prompt
        }
    }
    func answerApplet(_ accepted: Bool) {
        guard let prompt = applet else { return }
        appletText.withCString { ryu_ui_answer(prompt.id, accepted ? 1 : 0, $0) }
        applet = nil
    }
}

final class RendererSurface: UIView {
    var onReady: ((CAMetalLayer) -> Void)?
    var guestTouch = false
    private var fingers: [ObjectIdentifier: Int32] = [:]
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.allowsNextDrawableTimeout = true
        backgroundColor = .black
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func forward(_ touches: Set<UITouch>, down: Bool) {
        guard guestTouch, bounds.width > 0, bounds.height > 0 else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if fingers[key] == nil, down, let free = (Int32(0)..<16).first(where: { !fingers.values.contains($0) }) { fingers[key] = free }
            guard let finger = fingers[key] else { continue }
            let point = touch.location(in: self)
            ryu_touch_finger(finger, down ? 1 : 0, Int32(max(0, min(1279, point.x * 1280 / bounds.width))), Int32(max(0, min(719, point.y * 720 / bounds.height))))
            if !down { fingers.removeValue(forKey: key) }
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, down: true) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, down: true) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, down: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, down: false) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(window?.screen.scale ?? traitCollection.displayScale,
            min(1280 / bounds.width, 720 / bounds.height))
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(1, (bounds.width * scale).rounded()),
            height: max(1, (bounds.height * scale).rounded()))
        DispatchQueue.main.async { [weak self] in
            if let self { self.onReady?(self.metalLayer) }
        }
    }
}

struct MetalSurfaceView: UIViewRepresentable {
    var guestTouch = false
    let ready: (CAMetalLayer) -> Void
    func makeUIView(context: Context) -> RendererSurface {
        let view = RendererSurface(frame: .zero)
        view.onReady = ready
        view.guestTouch = guestTouch
        return view
    }
    func updateUIView(_ view: RendererSurface, context: Context) {
        view.onReady = ready
    }
}

struct GraphicsDisplay: View {
    @ObservedObject var model: GraphicsCheck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var metalLayer: CAMetalLayer?
    @State private var closeRequested = false

    var body: some View {
        if model.isGuest { PlayScreen(model: model) }
        else { rendererBody }
    }
    private var rendererBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MetalSurfaceView { if metalLayer !== $0 { metalLayer = $0 } }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(model.isGuest ? "Real homebrew graphics" : "Expected display: red, green, blue and white quadrants.")
                        .font(.headline)
                    Text(model.isGuest ? "The bundled demo draws a coloured triangle on a blue background, then exits. Imported NROs run until they exit or you stop them. Audio and touch/controller input are being developed." : "This checks the production renderer and screen presentation.")
                        .foregroundStyle(.secondary)
                    if model.isRunning {
                        ProgressView(model.isGuest ? "Homebrew running…" : "Rendering and checking pixels…")
                        if model.isGuest { Text("Guest frames: \(model.frames)").monospacedDigit() }
                    }
                    Button(model.isGuest ? "Launch homebrew" : (model.passed ? "Run renderer test again" : "Run renderer test")) {
                        if let metalLayer { model.run(layer: metalLayer) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(metalLayer == nil || model.isRunning || model.needsRestart)
                    if model.needsRestart { Text("Close and reopen the app before further execution tests.") }
                    if !model.report.isEmpty {
                        Text(model.report).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }.padding(24)
            }
            .navigationTitle(model.isGuest ? "Homebrew" : "Renderer display test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isRunning ? "Cancel and close" : "Close") {
                        if model.isRunning { closeRequested = true; model.cancel() }
                        else { dismiss() }
                    }
                }
            }
            .onChange(of: model.isRunning) { _, running in
                if !running && closeRequested { dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && model.isRunning { model.cancel() }
            }
            .onDisappear { model.cancel() }
            .interactiveDismissDisabled(model.isRunning)
        }
    }
}

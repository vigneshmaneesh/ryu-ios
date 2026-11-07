import Combine
import Foundation
import Metal
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class GraphicsCheck: ObservableObject {
    @Published var isRunning = false
    @Published var report = ""
    @Published var passed = false
    @Published var needsRestart = false

    init() {
        if let saved = Self.savedTrace() { report = "Previous renderer run:\n" + saved }
    }

    nonisolated private static func savedTrace() -> String? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: support.appendingPathComponent("RyuCore/graphics-last-run.log")) else { return nil }
        return String(decoding: data.suffix(48 * 1024), as: UTF8.self)
    }

    func run(layer: CAMetalLayer) {
        guard !isRunning, !needsRestart, layer.drawableSize.width > 0, layer.drawableSize.height > 0 else { return }
        ryu_graphics_prepare()
        isRunning = true
        passed = false
        report = "Initializing the upstream Vulkan renderer…"
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
                var output = [CChar](repeating: 0, count: 4096)
                status = library.withCString { lib in
                    directory.path.withCString { path in
                        output.withUnsafeMutableBufferPointer { buffer in
                            ryu_graphics_check(lib, Unmanaged.passUnretained(layer).toOpaque(), width, height,
                                path, buffer.baseAddress, buffer.count)
                        }
                    }
                }
                message = output.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if let saved = Self.savedTrace() { message += "\n\nSaved renderer trace:\n" + saved }
            } catch { message = "Could not initialize renderer storage: \(error.localizedDescription)" }
            let completedStatus = status
            let completedMessage = message
            Task { @MainActor in
                self?.isRunning = false
                self?.passed = completedStatus == 0
                self?.needsRestart = completedStatus < 0
                self?.report = completedMessage
            }
        }
    }

    func cancel() { ryu_graphics_cancel() }
}

private final class RendererSurface: UIView {
    var onReady: ((CAMetalLayer) -> Void)?
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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

private struct MetalSurfaceView: UIViewRepresentable {
    let ready: (CAMetalLayer) -> Void
    func makeUIView(context: Context) -> RendererSurface {
        let view = RendererSurface(frame: .zero)
        view.onReady = ready
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MetalSurfaceView { if metalLayer !== $0 { metalLayer = $0 } }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Expected display: red, green, blue and white quadrants.")
                        .font(.headline)
                    Text("This tests the production renderer and screen presentation. Guest graphics and game loading are still being integrated.")
                        .foregroundStyle(.secondary)
                    if model.isRunning { ProgressView("Rendering and checking pixels…") }
                    Button(model.passed ? "Run renderer test again" : "Run renderer test") {
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
            .navigationTitle("Renderer display test")
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

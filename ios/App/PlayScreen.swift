import SwiftUI

struct PlayScreen: View {
    @ObservedObject var model: GraphicsCheck
    @StateObject private var input = GameInput()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var launched = false
    @State private var closeRequested = false
    @State private var paused = false
    @State private var showingMenu = false
    @State private var confirmStop = false
    @State private var showHUD = true
    @State private var fullscreen = false
    @State private var focusPaused = false
    @State private var focusVolume: Double?
    private var configuration: [String: Any] { SessionControl.configuration(model.programURL) }
    private var aspect: CGFloat? {
        switch configuration["AspectRatio"] as? String ?? "Fixed16x9" {
        case "Fixed4x3": return 4 / 3
        case "Fixed16x10": return 16 / 10
        case "Fixed21x9": return 21 / 9
        case "Fixed32x9": return 32 / 9
        case "Stretched": return nil
        default: return 16 / 9
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                MetalSurfaceView(guestTouch: true) { layer in
                    if !launched { launched = true; input.start(program: model.programURL); model.run(layer: layer) }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    if showHUD { HStack {
                        Text(input.controllerName).font(.caption)
                        Spacer()
                        Text("\(model.fps) FPS").font(.caption.monospacedDigit())
                    }.padding(10).background(.black.opacity(0.45)) }
                    Spacer()
                    if model.isRunning && input.showTouch {
                        HStack(alignment: .bottom) {
                            VStack(spacing: 10) {
                                HStack { HeldButton(title: "L", bit: 6, input: input, size: 34); HeldButton(title: "ZL", bit: 8, input: input, size: 34) }
                                TouchStick(input: input)
                                HStack { HeldButton(title: "←", bit: 12, input: input, size: 30); HeldButton(title: "↑", bit: 13, input: input, size: 30); HeldButton(title: "↓", bit: 15, input: input, size: 30); HeldButton(title: "→", bit: 14, input: input, size: 30) }
                            }
                            Spacer(minLength: 4)
                            VStack {
                                Text(model.programURL == nil ? "Catch the targets\nStick or touch to move · A boost/beep · B reset" : "Player 1 · touch and controller input")
                                    .font(.caption2).multilineTextAlignment(.center).padding(8).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                HStack { HeldButton(title: "−", bit: 11, input: input, size: 32); HeldButton(title: "+", bit: 10, input: input, size: 32) }
                                HStack { HeldButton(title: "L3", bit: 4, input: input, size: 32); HeldButton(title: "R3", bit: 5, input: input, size: 32) }
                            }
                            Spacer(minLength: 4)
                            VStack(spacing: 6) {
                                HStack { HeldButton(title: "ZR", bit: 9, input: input, size: 34); HeldButton(title: "R", bit: 7, input: input, size: 34) }
                                HeldButton(title: "X", bit: 2, input: input)
                                HStack(spacing: 30) { HeldButton(title: "Y", bit: 3, input: input); HeldButton(title: "A", bit: 0, input: input) }
                                HeldButton(title: "B", bit: 1, input: input)
                                TouchStick(input: input, right: true).scaleEffect(0.7).frame(width: 78, height: 78)
                            }
                        }.id(paused).padding(14).scaleEffect(input.touchScale, anchor: .bottom).opacity(paused ? 0.3 : input.touchOpacity).allowsHitTesting(!paused)
                    }
                }
                if paused { Text("Paused").font(.title.bold()).padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) }
                if model.isRunning && model.frames == 0 { ProgressView("Starting game…").padding(20).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)) }
                if launched && !model.isRunning {
                    VStack(spacing: 14) {
                        Text(model.passed ? "Session finished" : "Session stopped").font(.headline)
                        ScrollView { Text(model.report).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.frame(maxHeight: 220)
                        Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                    }.padding(24).frame(maxWidth: 580).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
            .foregroundStyle(.white)
            .navigationTitle(model.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar(fullscreen ? .hidden : .visible, for: .navigationBar)
            .overlay(alignment: .topLeading) { if fullscreen { Button { showingMenu = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title).padding(12).background(.black.opacity(0.4), in: Circle()) }.padding() } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") {
                        togglePause()
                    }.disabled(!model.isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Menu", systemImage: "ellipsis.circle") { showingMenu = true }.disabled(!model.isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isRunning ? "Stop" : "Close") {
                        if model.isRunning { requestStop() } else { dismiss() }
                    }
                }
            }
            .onChange(of: model.isRunning) { _, running in
                if !running { input.stop(); paused = false; if closeRequested { dismiss() } }
            }
            .onChange(of: scenePhase) { _, phase in
                guard model.isRunning else { return }
                if phase == .active {
                    input.blockInput(false)
                    if let volume = focusVolume { SessionControl.send(1, volume); focusVolume = nil }
                    if focusPaused { focusPaused = false; if paused { togglePause() } }
                } else {
                    let action = configuration["FocusLostActionType"] as? String ?? "PauseEmulation"
                    if action == "BlockInput" || action == "BlockInputAndMuteAudio" { input.blockInput(true) }
                    if action == "MuteAudio" || action == "BlockInputAndMuteAudio", focusVolume == nil { focusVolume = Double(model.session.volume); SessionControl.send(1, 0) }
                    if phase == .background || action == "PauseEmulation", !paused { focusPaused = true; togglePause() }
                }
            }
            .onDisappear { input.stop(); model.cancel() }
            .interactiveDismissDisabled(model.isRunning)
            .onAppear { showHUD = !(configuration["StartNoUI"] as? Bool ?? false); fullscreen = configuration["StartFullscreen"] as? Bool ?? false }
            .sheet(isPresented: $showingMenu) {
                NavigationStack { PlayMenu(model: model, paused: paused, pause: togglePause, stop: { showingMenu = false; requestStop() })
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button(showHUD ? "Hide HUD" : "Show HUD") { showHUD.toggle() } }; ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingMenu = false } } }
                }
            }
            .confirmationDialog("Stop this game? Unsaved progress may be lost.", isPresented: $confirmStop, titleVisibility: .visible) { Button("Stop game", role: .destructive, action: stopGame) }
            .alert(model.applet?.title ?? "Game", isPresented: promptBinding(choices: false)) {
                if model.applet?.kind == 1 { TextField("Text", text: $model.appletText) }
                Button("OK") { model.answerApplet(true) }
                    .disabled(model.applet?.kind == 1 && model.appletText.utf16.count < (model.applet?.minimum ?? 0))
                Button("Cancel", role: .cancel) { model.answerApplet(false) }
            } message: { Text(model.applet?.message ?? "") }
            .confirmationDialog(model.applet?.title ?? "Game", isPresented: promptBinding(choices: true), titleVisibility: .visible) {
                ForEach(model.applet?.choices ?? []) { choice in
                    Button(choice.name) { if model.applet?.kind == 3 { input.configurePlayers(choice.id) }; model.answerChoice(choice.id) }
                }
                Button("Cancel", role: .cancel) { model.answerApplet(false) }
            } message: { Text(model.applet?.message ?? "") }
            .onChange(of: model.appletText) { _, value in
                let maximum = model.applet?.maximum ?? 1024
                if value.count > maximum { model.appletText = String(value.prefix(maximum)) }
            }
        }
        .preferredColorScheme(.dark)
    }
    private func promptBinding(choices: Bool) -> Binding<Bool> {
        Binding(get: { guard let prompt = model.applet else { return false }; return choices ? prompt.kind >= 2 : prompt.kind < 2 }, set: { visible in
            if !visible, let id = model.applet?.id { DispatchQueue.main.async { if model.applet?.id == id { model.answerApplet(false) } } }
        })
    }
    private func togglePause() { input.releaseVirtual(); paused.toggle(); input.setPaused(paused); ryu_pause(paused ? 1 : 0) }
    private func requestStop() { if configuration["ShowConfirmExit"] as? Bool ?? true { confirmStop = true } else { stopGame() } }
    private func stopGame() { closeRequested = true; input.stop(); model.cancel() }
}

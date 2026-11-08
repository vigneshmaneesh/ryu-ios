import SwiftUI

struct PlayScreen: View {
    @ObservedObject var model: GraphicsCheck
    @StateObject private var input = GameInput()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var launched = false
    @State private var closeRequested = false
    @State private var paused = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                MetalSurfaceView(guestTouch: true) { layer in
                    if !launched { launched = true; input.start(program: model.programURL); model.run(layer: layer) }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    HStack {
                        Text(input.controllerName).font(.caption)
                        Spacer()
                        Text("\(model.fps) FPS").font(.caption.monospacedDigit())
                    }.padding(10).background(.black.opacity(0.45))
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") {
                        input.releaseVirtual(); paused.toggle(); input.setPaused(paused); ryu_pause(paused ? 1 : 0)
                    }.disabled(!model.isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isRunning ? "Stop" : "Close") {
                        if model.isRunning { closeRequested = true; input.stop(); model.cancel() } else { dismiss() }
                    }
                }
            }
            .onChange(of: model.isRunning) { _, running in
                if !running { input.stop(); paused = false; if closeRequested { dismiss() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && model.isRunning { input.releaseVirtual(); paused = true; input.setPaused(true); ryu_pause(1) }
            }
            .onDisappear { input.stop(); model.cancel() }
            .interactiveDismissDisabled(model.isRunning)
            .alert(model.applet?.title ?? "Game", isPresented: Binding(get: { model.applet != nil }, set: { if !$0 { model.answerApplet(false) } })) {
                if model.applet?.kind == 1 { TextField("Text", text: $model.appletText) }
                Button("OK") { model.answerApplet(true) }
                    .disabled(model.applet?.kind == 1 && model.appletText.utf16.count < (model.applet?.minimum ?? 0))
                Button("Cancel", role: .cancel) { model.answerApplet(false) }
            } message: { Text(model.applet?.message ?? "") }
            .onChange(of: model.appletText) { _, value in
                let maximum = model.applet?.maximum ?? 1024
                if value.count > maximum { model.appletText = String(value.prefix(maximum)) }
            }
        }
        .preferredColorScheme(.dark)
    }
}

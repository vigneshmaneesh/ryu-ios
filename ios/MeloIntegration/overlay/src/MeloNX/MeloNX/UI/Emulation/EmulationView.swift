//
//  EmulationView.swift
//  MeloNX
//
//  Created by Stossy11 on 23/4/2026.
//  iOS integration: keep the host menu above the gameplay layers.
//

import SwiftUI
import Melo_Controller
import Combine

struct EmulationView: View {
    var game: GameInfo
    @EnvironmentObject var ryujinxController: RyujinxController
    @StateObject var controllerManager: ControllerManager = .shared
    @StateObject var statisticsHandler: StatisticsHandler = .init()
    @StateObject private var nativeSettingsManager: NativeSettingsManager = .shared

    @State var isConnected = false
    @State private var isMenuVisible = false
    @State private var hideMenuTask: Task<Void, Never>?

    @ViewBuilder
    func emulationView(_ airplay: Bool = false) -> some View {
        if airplay {
            MetalViewRepresentable(showView: true)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MetalViewContainer(showView: !isConnected, airplay: airplay,
                               ryujinxController: ryujinxController,
                               statisticsHandler: statisticsHandler,
                               nativeSettingsManager: nativeSettingsManager)
                .overlay {
                    if controllerManager.hasVirtualController() {
                        ControllerView(controller: VirtualControllerManager.shared,
                                       isEditing: false, gameId: game.titleId,
                                       gameName: game.titleName)
                            .opacity(nativeSettingsManager.setting(forKey: "On-ScreenControllerOpacity", default: 1.0).value)
                            .ignoresSafeArea(.all, edges: .vertical)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            emulationView()
                .onAppear {
                    statisticsHandler.registerPush()
                    isConnected = Air.shared.connected
                    Air.shared.connectionCallbacks.append { self.isConnected = $0 }
                    Air.play(AnyView(emulationView(true)))
                }
                .onDisappear {
                    hideMenuTask?.cancel()
                    hideMenuTask = nil
                    isMenuVisible = false
                }
                .background {
                    GameMenuTapObserver(onTap: revealMenu)
                }
                .overlay {
                    if !statisticsHandler.started {
                        LoadingOverlayView(game: game, showLogs: false)
                    }
                }
                // Keep the menu mounted so fading its button doesn't destroy an
                // open native menu or controller settings sheet.
                .overlay(alignment: controllerManager.hasPhysicalController ? .top : .topTrailing) {
                    InGameConfigView()
                        .opacity(isMenuVisible ? 1 : 0)
                        .allowsHitTesting(isMenuVisible)
                        .accessibilityHidden(!isMenuVisible)
                        .padding(.top, max(12, geometry.safeAreaInsets.top + 8))
                        .padding(.horizontal, max(12, max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing) + 8))
                }
        }
    }

    @MainActor
    private func revealMenu() {
        hideMenuTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { isMenuVisible = true }
        hideMenuTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isMenuVisible = false }
        }
    }
}

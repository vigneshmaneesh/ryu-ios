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
                .overlay {
                    if !statisticsHandler.started {
                        LoadingOverlayView(game: game, showLogs: false)
                    }
                }
                // Keep the host menu above video, loading UI and virtual input.
                // Only the button receives taps; the remaining game area stays
                // available to the game's touchscreen and controller overlay.
                .overlay(alignment: .topTrailing) {
                    InGameConfigView()
                        .padding(.top, max(12, geometry.safeAreaInsets.top + 8))
                        .padding(.trailing, max(12, geometry.safeAreaInsets.trailing + 8))
                }
        }
    }
}

//
//  ContentView.swift
//  BeachRamp
//
//  Created by Don Browning on 3/10/26.
//

import SwiftUI
import BeachStatus

/// Root of the app: the sun-following ground and the board.
///
/// The sky is the app — the ground engine drives one gradient + token set for
/// every screen, ticking with the real sun. iPhone gets the single-scroll
/// board; iPad reuses it until the wide board lands.
struct ContentView: View {
    @State private var viewModel = BeachViewModel()
    @State private var ground: GroundModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// QA hook mirroring tvOS: `--sky-minutes N` freezes the ground at N
    /// minutes past midnight so any phase can be reviewed on demand.
    init() {
        let args = ProcessInfo.processInfo.arguments
        let minutes = args.firstIndex(of: "--sky-minutes")
            .flatMap { idx in args.indices.contains(idx + 1) ? Int(args[idx + 1]) : nil }
        let override = minutes.map {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval($0 * 60))
        }
        _ground = State(initialValue: GroundModel(overrideDate: override))
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    BoardiPadView(viewModel: viewModel)
                } else {
                    BoardiPhoneView(viewModel: viewModel)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Ramp.self) { ramp in
                RampDetailView(viewModel: viewModel, ramp: ramp)
            }
        }
        .fullScreenCover(isPresented: $viewModel.camPresented) {
            LiveCamFullscreenView(viewModel: viewModel)
                .environment(\.ground, ground.state)
        }
        .environment(\.ground, ground.state)
        .environment(\.skyPalette, ground.state.palette)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2), value: ground.state.altitude)
        .task {
            ground.start()
            // QA hook: --force-landscape rotates at launch (simulator panels
            // have no rotate control).
            if ProcessInfo.processInfo.arguments.contains("--force-landscape") {
                try? await Task.sleep(for: .seconds(1))
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
            }
            await viewModel.loadAll()
            #if DEBUG
            // QA hook: --ask-preview seeds the Ask section with a canned
            // answer (no model call) so the layout can be screenshot.
            // QA hook: --ask-listen behaves like the widget's Ask button
            // (beachinfo://ask?listen=1) without the simulator's open-URL prompt.
            if ProcessInfo.processInfo.arguments.contains("--ask-listen") {
                try? await Task.sleep(for: .seconds(1.5))
                viewModel.askListenToken += 1
            }
            if ProcessInfo.processInfo.arguments.contains("--ask-preview") {
                if !viewModel.chat.hasKey { viewModel.chat.saveKey("preview") }
                viewModel.chat.load(turns: [
                    ChatTurn(role: .user, text: "what time will NSB close today?"),
                    ChatTurn(role: .assistant, text: PreviewAsk.reply),
                ], sources: PreviewAsk.sources)
            }
            #endif
            // Foreground poll on the ingester's own cadence. Without it the
            // stale state would trip simply from leaving the board open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await viewModel.refresh()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onOpenURL { url in
            // beachinfo://ask?listen=1 from a widget's Ask button: straight
            // into the Ask bar, listening — no Siri in between.
            guard url.scheme == "beachinfo", url.host == "ask" else { return }
            viewModel.askListenToken += 1
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                ground.refresh()
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

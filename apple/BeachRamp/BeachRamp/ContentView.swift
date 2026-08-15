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
            BoardiPhoneView(viewModel: viewModel)
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.ground, ground.state)
        .environment(\.skyPalette, ground.state.palette)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2), value: ground.state.altitude)
        .task {
            ground.start()
            await viewModel.loadAll()
        }
        .refreshable {
            await viewModel.refresh()
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

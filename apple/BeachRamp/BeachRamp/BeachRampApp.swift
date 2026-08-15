//
//  BeachRampApp.swift
//  BeachRamp
//
//  Created by Don Browning on 3/10/26.
//

import SwiftUI
import AVFoundation
import BeachStatus

@main
struct BeachRampApp: App {
    init() {
        BeachFont.registerFonts()
        // The beach cam plays silent video, but AVPlayer defaults to the
        // `.soloAmbient` session category, which stops other apps' audio (e.g.
        // music) the moment a player starts. Use `.ambient` so our playback
        // mixes silently alongside whatever else is playing instead of
        // interrupting it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  BeachRampTVApp.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import UIKit
import AVFoundation

@main
struct BeachRampTVApp: App {
    init() {
        // The beach cam plays silent video, but AVPlayer defaults to the
        // `.soloAmbient` session category, which stops other apps' audio the
        // moment a player starts. Use `.ambient` so our playback mixes silently
        // alongside whatever else is playing instead of interrupting it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}

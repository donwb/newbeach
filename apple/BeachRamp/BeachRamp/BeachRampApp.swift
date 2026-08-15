//
//  BeachRampApp.swift
//  BeachRamp
//
//  Created by Don Browning on 3/10/26.
//

import SwiftUI
import AVFoundation
import BeachStatus

/// Exists only to force-and-hold landscape while the live cam is up. UIKit
/// asks this on every rotation; views set `orientationMask` before calling
/// `requestGeometryUpdate` so the rotation both happens and sticks.
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

@main
struct BeachRampApp: App {
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var delegate

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

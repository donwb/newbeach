//
//  TVVideoPlayerView.swift
//  BeachRampTV
//
//  Created by Don Browning on 4/6/26.
//

import SwiftUI
import AVKit

/// HLS video player panel for the tvOS dashboard.
/// Designed as a panoramic banner (1280x270 source, ~4.7:1 aspect ratio).
struct TVVideoPlayerView: View {
    let url: URL
    /// Increments on every refresh attempt, even when `url` is unchanged.
    /// Watching this lets us rebuild AVPlayer for recovery cases where the
    /// re-resolved YouTube URL string happens to match the old one but the
    /// player is wedged.
    let rebuildToken: Int
    @Binding var isPlaying: Bool
    /// Called when AVPlayer reports a playback failure. The owner should ask
    /// the API to re-resolve the rotating YouTube HLS URL and update `url`.
    var onPlaybackFailure: (() -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var failureObserver: PlayerFailureObserver?
    @State private var stallWatcher: PlayerStallWatcher?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(1280.0/270.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.05))
                    .aspectRatio(1280.0/270.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        Image(systemName: "video.slash")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stallWatcher = nil
            failureObserver = nil
            player?.pause()
            player = nil
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: url) { _, newURL in
            setupPlayer(url: newURL)
        }
        .onChange(of: rebuildToken) { _, _ in
            // The owner asked for a rebuild — usually after a playback failure
            // where the re-resolved URL came back identical. Tear down and
            // create a fresh AVPlayer; that's the only reliable way to clear
            // a wedged AVPlayerItem.
            setupPlayer()
        }
    }

    private func setupPlayer(url override: URL? = nil) {
        // Explicitly tear down the prior player so it stops any background
        // network work before we replace it. ARC would eventually deinit it
        // but a wedged AVPlayer can keep retrying segment loads in the meantime.
        stallWatcher = nil
        failureObserver = nil
        if let oldPlayer = player {
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
        }

        let streamURL = override ?? url
        let item = AVPlayerItem(url: streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = false

        failureObserver = PlayerFailureObserver(item: item, player: newPlayer) {
            onPlaybackFailure?()
        }
        stallWatcher = PlayerStallWatcher(player: newPlayer) {
            onPlaybackFailure?()
        }

        player = newPlayer
        if isPlaying {
            newPlayer.play()
        }
    }
}

/// Observes AVPlayer/AVPlayerItem failure signals and invokes a callback.
/// Wired up once per AVPlayerItem; replaced when the URL changes.
private final class PlayerFailureObserver {
    private let onFailure: () -> Void
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var notificationToken: NSObjectProtocol?

    init(item: AVPlayerItem, player: AVPlayer, onFailure: @escaping () -> Void) {
        self.onFailure = onFailure

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                self?.fire()
            }
        }

        errorObservation = player.observe(\.error, options: [.new]) { [weak self] player, _ in
            if player.error != nil {
                self?.fire()
            }
        }

        notificationToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.fire()
        }
    }

    deinit {
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func fire() {
        DispatchQueue.main.async { [onFailure] in
            onFailure()
        }
    }
}

/// Polls AVPlayer's currentTime to catch the case where the player is wedged
/// without ever firing a KVO/notification failure. HLS players can buffer
/// indefinitely against a stale manifest without setting `.failed` status, so
/// the explicit failure observers alone aren't enough.
private final class PlayerStallWatcher {
    private let onStall: () -> Void
    private weak var player: AVPlayer?
    private var timer: Timer?
    private var lastTime: CMTime = .zero
    private var lastProgressAt: Date = Date()
    private var hasFired = false

    /// Treat the player as stalled if currentTime hasn't advanced for this long
    /// while the player is supposed to be playing. 15s comfortably exceeds
    /// normal HLS rebuffering windows.
    private static let stallThreshold: TimeInterval = 15

    init(player: AVPlayer, onStall: @escaping () -> Void) {
        self.player = player
        self.onStall = onStall

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        guard !hasFired, let player else { return }
        // Only watch when we're actually trying to play. `timeControlStatus`
        // distinguishes paused vs. waiting-to-play vs. playing.
        let status = player.timeControlStatus
        guard status == .playing || status == .waitingToPlayAtSpecifiedRate else {
            lastProgressAt = Date()
            lastTime = player.currentTime()
            return
        }

        let now = player.currentTime()
        if CMTimeCompare(now, lastTime) != 0 {
            lastTime = now
            lastProgressAt = Date()
            return
        }

        if Date().timeIntervalSince(lastProgressAt) >= Self.stallThreshold {
            hasFired = true  // fire once per watcher; the rebuild will replace us
            DispatchQueue.main.async { [onStall] in
                onStall()
            }
        }
    }
}

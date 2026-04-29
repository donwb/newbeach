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
    @Binding var isPlaying: Bool
    /// Called when AVPlayer reports a playback failure. The owner should ask
    /// the API to re-resolve the rotating YouTube HLS URL and update `url`.
    var onPlaybackFailure: (() -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var failureObserver: PlayerFailureObserver?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.system(size: 16))
                Text("Beach Cam")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)

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
    }

    private func setupPlayer(url override: URL? = nil) {
        let streamURL = override ?? url
        let item = AVPlayerItem(url: streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = false

        failureObserver = PlayerFailureObserver(item: item, player: newPlayer) {
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

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

    @State private var player: AVPlayer?

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
        let newPlayer = AVPlayer(url: streamURL)
        newPlayer.isMuted = false
        player = newPlayer
        if isPlaying {
            newPlayer.play()
        }
    }
}

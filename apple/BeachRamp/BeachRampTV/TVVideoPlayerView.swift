//
//  TVVideoPlayerView.swift
//  BeachRampTV
//
//  Created by Don Browning on 4/6/26.
//

import SwiftUI
import AVKit

/// HLS video player panel for the tvOS dashboard.
/// Matches the card style of the tide and weather sections.
struct TVVideoPlayerView: View {
    let url: URL
    @Binding var isPlaying: Bool

    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                Text("Beach Cam")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)

            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.05))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
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

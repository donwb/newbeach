import SwiftUI
import AVKit

/// Panoramic HLS beach-cam banner for the iPad layout — full width, ~4.7:1.
/// Adapted from the tvOS `TVVideoPlayerView`; reuses the same failure/stall
/// recovery so a rotated YouTube manifest re-resolves automatically.
struct BeachCamView: View {
    let url: URL
    /// Increments on every refresh attempt, even when `url` is unchanged, so the
    /// player rebuilds for wedged-but-same-URL recovery cases.
    let rebuildToken: Int
    /// Called when AVPlayer reports a playback failure; owner re-resolves the URL.
    var onPlaybackFailure: (() -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var isMuted = true
    @State private var failureObserver: BeachCamFailureObserver?
    @State private var stallWatcher: BeachCamStallWatcher?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Label("Beach Cam", systemImage: "video.fill")
                    .font(.headline)
                Spacer()
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.oceanAccent)
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.oceanAccent)
            }

            if let player {
                // Fit (not fill) so the whole panorama shows at full width;
                // height follows the aspect ratio — shorter in portrait, taller
                // in landscape — with no center-cropping.
                VideoPlayer(player: player)
                    .aspectRatio(1280.0 / 270.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.nestedCardBackground)
                    .aspectRatio(1280.0 / 270.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image(systemName: "video.slash")
                            .font(.title)
                            .foregroundStyle(AppColors.secondaryText)
                    }
            }
        }
        .padding()
        .cardSurface()
        .onAppear { setupPlayer() }
        .onDisappear {
            stallWatcher = nil
            failureObserver = nil
            player?.pause()
            player = nil
        }
        .onChange(of: isPlaying) { _, playing in
            playing ? player?.play() : player?.pause()
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
        .onChange(of: url) { _, newURL in setupPlayer(url: newURL) }
        .onChange(of: rebuildToken) { _, _ in setupPlayer() }
    }

    private func setupPlayer(url override: URL? = nil) {
        stallWatcher = nil
        failureObserver = nil
        if let oldPlayer = player {
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
        }

        let streamURL = override ?? url
        let item = AVPlayerItem(url: streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted

        failureObserver = BeachCamFailureObserver(item: item, player: newPlayer) {
            onPlaybackFailure?()
        }
        stallWatcher = BeachCamStallWatcher(player: newPlayer) {
            onPlaybackFailure?()
        }

        player = newPlayer
        if isPlaying {
            newPlayer.play()
        }
    }
}

/// Observes AVPlayer/AVPlayerItem failure signals and invokes a callback.
private final class BeachCamFailureObserver {
    private let onFailure: () -> Void
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var notificationToken: NSObjectProtocol?

    init(item: AVPlayerItem, player: AVPlayer, onFailure: @escaping () -> Void) {
        self.onFailure = onFailure

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { self?.fire() }
        }
        errorObservation = player.observe(\.error, options: [.new]) { [weak self] player, _ in
            if player.error != nil { self?.fire() }
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
        DispatchQueue.main.async { [onFailure] in onFailure() }
    }
}

/// Polls AVPlayer's currentTime to catch a wedged player that never fires a
/// failure signal (HLS can buffer indefinitely against a stale manifest).
private final class BeachCamStallWatcher {
    private let onStall: () -> Void
    private weak var player: AVPlayer?
    private var timer: Timer?
    private var lastTime: CMTime = .zero
    private var lastProgressAt: Date = Date()
    private var hasFired = false

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

    deinit { timer?.invalidate() }

    private func tick() {
        guard !hasFired, let player else { return }
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
            hasFired = true
            DispatchQueue.main.async { [onStall] in onStall() }
        }
    }
}

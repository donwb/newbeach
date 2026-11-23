import SwiftUI
import BeachStatus

/// The 340pt picture band. The panorama is the app: nothing is ever drawn on
/// this band — no scrim, no headline, no floating panel, at any time. When
/// the selected cam has no live video the band shows the cam's still (the
/// YouTube live thumbnail, refreshed every few minutes — `CamStill`), or a
/// plain dark field when there's no lit still either; the cam strip does the
/// messaging, keeping the no-overlay rule intact.
///
/// Layers, bottom up: dark field → still → video. The still loads even while
/// video plays, so a cam switch or a stalled player (the player view is clear
/// until it has frames) reveals the beach instead of black.
///
/// The crop: the relay streams the vendor's full frame at 1280×270 (see
/// docs/CAM-RELAY.md), which carries a baked-in AccuWeather badge in its top
/// rows. At 1920 wide the frame renders 405pt tall; clipping the top 65pt
/// yields the design's 1920×340 band and removes the badge entirely
/// (badge bottom ≈ 34 source px ≈ 51 display pt). Crop is client-side on
/// purpose — the relay stays `-c copy`. The still is cropped to the same
/// 1280×270 band (`CamStill.band`), so it takes the identical trim. If the
/// restreamer's output geometry ever changes, retune
/// `fullFrameHeight`/`badgeCropPt` together.
struct PictureBand: View {
    /// 1280×270 source at 1920 wide → 1920×405.
    static let fullFrameHeight: CGFloat = 405
    /// Display points clipped off the top of the frame.
    static let badgeCropPt: CGFloat = fullFrameHeight - TVMetrics.picture

    let streamURL: URL?
    let rebuildToken: Int
    @Binding var isPlaying: Bool
    /// True when the roster's selected cam has no live video.
    let selectedOffline: Bool
    /// The selected cam's latest lit still, cropped to the panorama band.
    var stillImage: CGImage? = nil
    let onPlaybackFailure: () -> Void
    /// Lit/black picture reads for the cam-switching dark watch.
    var onPictureSample: (Bool) -> Void = { _ in }

    var body: some View {
        Color(boardHex: 0x05080C)
            .overlay(alignment: .top) {
                if let stillImage {
                    Image(decorative: stillImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: Self.fullFrameHeight)
                        .offset(y: -Self.badgeCropPt)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if !selectedOffline, let streamURL {
                    TVVideoPlayerView(
                        url: streamURL,
                        rebuildToken: rebuildToken,
                        isPlaying: $isPlaying,
                        onPlaybackFailure: onPlaybackFailure,
                        onPictureSample: onPictureSample
                    )
                    .frame(height: Self.fullFrameHeight)
                    .offset(y: -Self.badgeCropPt)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: stillImage.map { ObjectIdentifier($0) })
            .frame(height: TVMetrics.picture)
            .clipped()
            .accessibilityIdentifier("pictureBand")
            .accessibilityValue(selectedOffline ? (stillImage == nil ? "dark" : "still") : "live")
    }
}

#if DEBUG
#Preview("Offline", traits: .fixedLayout(width: 1920, height: 340)) {
    @Previewable @State var playing = false
    PictureBand(
        streamURL: nil,
        rebuildToken: 0,
        isPlaying: $playing,
        selectedOffline: true,
        onPlaybackFailure: {}
    )
}

#Preview("Still fallback", traits: .fixedLayout(width: 1920, height: 340)) {
    @Previewable @State var playing = false
    PictureBand(
        streamURL: nil,
        rebuildToken: 0,
        isPlaying: $playing,
        selectedOffline: true,
        stillImage: PreviewFixtures.camStill,
        onPlaybackFailure: {}
    )
}
#endif

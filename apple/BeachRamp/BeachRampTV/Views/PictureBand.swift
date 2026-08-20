import SwiftUI
import BeachStatus

/// The 340pt picture band. The panorama is the app: nothing is ever drawn on
/// this band — no scrim, no headline, no floating panel, at any time. When
/// the selected cam is offline the band holds a plain dark field and the cam
/// strip does the messaging (strikethrough + live-neighbor hint), keeping
/// the no-overlay rule intact.
///
/// The crop: the relay streams the vendor's full frame at 1280×270 (see
/// docs/CAM-RELAY.md), which carries a baked-in AccuWeather badge in its top
/// rows. At 1920 wide the frame renders 405pt tall; clipping the top 65pt
/// yields the design's 1920×340 band and removes the badge entirely
/// (badge bottom ≈ 34 source px ≈ 51 display pt). Crop is client-side on
/// purpose — the relay stays `-c copy`. If the restreamer's output geometry
/// ever changes, retune `fullFrameHeight`/`badgeCropPt` together.
struct PictureBand: View {
    /// 1280×270 source at 1920 wide → 1920×405.
    static let fullFrameHeight: CGFloat = 405
    /// Display points clipped off the top of the frame.
    static let badgeCropPt: CGFloat = fullFrameHeight - TVMetrics.picture

    let streamURL: URL?
    let rebuildToken: Int
    @Binding var isPlaying: Bool
    /// True when the roster's selected cam has no resolved stream.
    let selectedOffline: Bool
    let onPlaybackFailure: () -> Void

    var body: some View {
        Color.black
            .overlay(alignment: .top) {
                if !selectedOffline, let streamURL {
                    TVVideoPlayerView(
                        url: streamURL,
                        rebuildToken: rebuildToken,
                        isPlaying: $isPlaying,
                        onPlaybackFailure: onPlaybackFailure
                    )
                    .frame(height: Self.fullFrameHeight)
                    .offset(y: -Self.badgeCropPt)
                } else {
                    // Offline: a flat dark field. The cam strip carries the
                    // words; nothing is drawn on the glass, even now.
                    Color(boardHex: 0x05080C)
                }
            }
            .frame(height: TVMetrics.picture)
            .clipped()
            .accessibilityIdentifier("pictureBand")
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
#endif

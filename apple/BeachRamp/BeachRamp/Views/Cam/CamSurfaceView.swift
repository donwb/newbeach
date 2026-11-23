import SwiftUI
import BeachStatus

/// The selected cam's picture at the panorama's 1280×270 aspect: live video
/// when the relay is streaming, otherwise the cam's still (`CamStill`, the
/// YouTube live thumbnail refreshed every few minutes), otherwise flat deep
/// water. Every iOS cam surface (iPad rail and column, the landscape cam)
/// goes through here so they agree with each other and with the badge.
///
/// With no live video the player isn't built at all: pointing AVPlayer at a
/// dark relay path only fails, rebuilds and re-fetches the roster every 10s.
struct CamSurfaceView: View {
    @Bindable var viewModel: BeachViewModel

    var body: some View {
        let mode = viewModel.camMode
        ZStack {
            CamSurfaceView.deepWater

            if mode == .live {
                BeachCamView(
                    url: viewModel.videoStreamURL,
                    rebuildToken: viewModel.videoStreamGeneration,
                    onPlaybackFailure: { viewModel.refreshVideoStream() },
                    onPictureSample: { viewModel.notePicture(lit: $0) }
                )
            } else if mode == .still, let still = viewModel.camStill.image {
                Image(decorative: still, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else if mode == .offline {
                Image(systemName: "video.slash")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .aspectRatio(CamStill.panoramaAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.6),
                   value: viewModel.camStill.image.map { ObjectIdentifier($0) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(mode))
    }

    static let deepWater = Color(red: 0x0A / 255, green: 0x14 / 255, blue: 0x20 / 255)

    private func accessibilityText(_ mode: CamMode) -> String {
        let name = viewModel.selectedCamera?.name ?? "Beach"
        switch mode {
        case .live: return "\(name) cam, live video"
        case .still: return "\(name) cam, still photo, refreshed every few minutes"
        case .offline: return "\(name) cam offline"
        }
    }
}

#if DEBUG
#Preview("Still fallback") {
    let vm = BeachViewModel.preview(camMode: .still)
    return CamSurfaceView(viewModel: vm)
        .padding()
}

#Preview("Offline") {
    let vm = BeachViewModel.preview(camMode: .offline)
    return CamSurfaceView(viewModel: vm)
        .padding()
}
#endif

import SwiftUI
import UIKit
import BeachStatus

/// The live cam as its own landscape surface. The panorama fills the frame;
/// a top scrim carries the LIVE mark, cam name, the other cams, and close;
/// the bottom scrim carries the verdict and the clock. The cam is sugar —
/// if the stream is dead the rest of the app is unaffected.
struct LiveCamFullscreenView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0x0A / 255, green: 0x14 / 255, blue: 0x20 / 255)
                .ignoresSafeArea()

            // Full-width letterbox: the whole 1280×270 panorama shows, with
            // deep-water bars above and below. Cropping the pano to fill the
            // frame threw away most of the beach.
            BeachCamView(
                url: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )
            .ignoresSafeArea()

            VStack {
                topScrim
                Spacer()
                bottomScrim
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // Slight delay so the cover's window is key before the request —
            // asking during the presentation transition gets silently denied.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                OrientationDelegate.orientationMask = .landscape
                Self.requestOrientation(.landscape)
            }
        }
        .onDisappear {
            OrientationDelegate.orientationMask = .all
            Self.requestOrientation(.portrait)
        }
    }

    private var topScrim: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: 0xE6 / 255, green: 0x3A / 255, blue: 0x2B / 255))
                    .frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(viewModel.selectedCamera?.name ?? "Beach cam")
                .font(.archivo(22, weight: .extraBold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // The other cams, right-aligned; scrolls when the roster is long.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.cameras) { camera in
                        let isActive = camera.id == viewModel.selectedCamera?.id
                        Button {
                            viewModel.selectCamera(camera.id)
                        } label: {
                            Text(camera.name)
                                .font(.archivo(13, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isActive ? .black : .white)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(isActive ? .white : .white.opacity(0.14))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
            }
            .frame(maxWidth: 420)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close cam")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 26)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var bottomScrim: some View {
        let verdict = viewModel.verdict()
        return HStack(alignment: .center, spacing: 12) {
            Rectangle()
                .fill(verdictColor(verdict.category))
                .frame(width: 8, height: 28)
            Text(verdict.headline)
                .font(.archivo(17, weight: .extraBold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            TimelineView(.everyMinute) { context in
                Text(SinceFormatter.clock(context.date))
                    .font(.archivo(13))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .combine)
    }

    private func verdictColor(_ category: StatusCategory) -> Color {
        switch category {
        case .open: Color(red: 0x2A / 255, green: 0xE0 / 255, blue: 0x7A / 255)
        case .limited: Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255)
        case .closed: Color(red: 0xE6 / 255, green: 0x3A / 255, blue: 0x2B / 255)
        }
    }

    /// Ask the scene for an orientation. Best-effort — on iPad the view also
    /// works in any orientation, so a denied request is harmless.
    private static func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
            #if DEBUG
            print("cam orientation request denied: \(error)")
            #endif
        }
    }
}

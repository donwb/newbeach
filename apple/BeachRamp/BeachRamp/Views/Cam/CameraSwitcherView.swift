import SwiftUI
import BeachStatus

/// The inline camera switcher: one chip per roster cam, active chip filled
/// with the accent. Lives above the board's inline cam on iPad; the
/// fullscreen cam has its own scrim-styled chips. Renders nothing until the
/// roster has a second camera to offer.
struct CameraSwitcherView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.ground) private var ground

    var body: some View {
        if viewModel.cameras.count > 1 {
            let t = ground.tokens
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.cameras) { camera in
                        let isActive = camera.id == viewModel.selectedCamera?.id
                        let unresolved = camera.url == nil
                        Button {
                            viewModel.selectCamera(camera.id)
                        } label: {
                            HStack(spacing: 5) {
                                if unresolved {
                                    Image(systemName: "video.slash")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(camera.name.uppercased())
                                    .font(.archivo(11, weight: .bold))
                                    .tracking(11 * ArchivoTracking.kicker)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(isActive ? .white : t.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(isActive ? t.accent : .clear)
                            .overlay {
                                if !isActive {
                                    Rectangle().strokeBorder(t.rule, lineWidth: 2)
                                }
                            }
                            .opacity(unresolved ? 0.45 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressTintButtonStyle())
                        .disabled(unresolved)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
            }
            .accessibilityLabel("Camera switcher")
        }
    }
}

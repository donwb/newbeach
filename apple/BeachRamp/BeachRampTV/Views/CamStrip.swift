import SwiftUI
import BeachStatus

/// The 56pt cam switcher under the picture: "WATCHING" plus every cam named
/// flat — a switcher, not a stepper, so a user checking three beaches a day
/// jumps instead of cycling. Active cam wears the 4pt sand underline; focus
/// moves switch the stream live (the channel-flip pattern — no Select
/// needed). Offline cams are struck through with an "offline since"
/// sub-label, and when the *selected* cam is dark the nearest live neighbor
/// is named in sand with a chevron pointing the way.
struct CamStrip: View {
    let cameras: [Camera]
    let selectedID: String?
    /// When each offline camera was first seen dark, keyed by id.
    let offlineSince: [String: Date]
    let focus: FocusState<RootFocus?>.Binding

    private var selectedCamera: Camera? {
        cameras.first { $0.id == selectedID } ?? cameras.first
    }

    private var selectedOffline: Bool {
        selectedCamera.map { $0.url == nil } ?? false
    }

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            Text("Watching")
                .tvLabel()
                .fixedSize()

            HStack(alignment: .center, spacing: 34) {
                ForEach(cameras) { camera in
                    Button {
                        // Focus already switched the stream; Select is a no-op
                        // by design, but stays a Button so the strip is a real
                        // focus row.
                    } label: {
                        CamStripName(
                            camera: camera,
                            isActive: camera.id == selectedCamera?.id,
                            isFocused: focus.wrappedValue == .cam(camera.id),
                            offlineSince: offlineSince[camera.id],
                            liveNeighborHint: liveNeighborHint(for: camera)
                        )
                    }
                    .buttonStyle(BareButtonStyle())
                    .focused(focus, equals: .cam(camera.id))
                    .accessibilityIdentifier("camStrip.\(camera.id)")
                    .accessibilityValue(camera.id == selectedCamera?.id ? "watching" : "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("‹ › to move")
                .tvLabel()
                .fixedSize()
        }
        .padding(.horizontal, TVMetrics.sidePad)
        .frame(height: TVMetrics.camStrip)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TVInk.rule).frame(height: 2)
        }
        .focusSection()
        .animation(.easeOut(duration: 0.15), value: focus.wrappedValue)
    }

    /// When the selected cam is dark, its nearest live neighbor gets the
    /// pointer. Order is geographic, so the neighbor may be either direction.
    private func liveNeighborHint(for camera: Camera) -> String? {
        guard selectedOffline, camera.url != nil,
              let selected = selectedCamera,
              let selectedIdx = cameras.firstIndex(where: { $0.id == selected.id }),
              let camIdx = cameras.firstIndex(where: { $0.id == camera.id })
        else { return nil }

        let liveIndices = cameras.indices.filter { cameras[$0].url != nil }
        guard let nearest = liveIndices.min(by: {
            abs($0 - selectedIdx) < abs($1 - selectedIdx)
        }), nearest == camIdx else { return nil }

        return camIdx > selectedIdx ? "live ›" : "‹ live"
    }
}

/// One cam name. Active = 28/extraBold + 4pt sand underline; inactive = 26
/// at 50%; focus brightens. All state nests under the name itself so the
/// strip never disagrees with what the remote does.
private struct CamStripName: View {
    let camera: Camera
    let isActive: Bool
    let isFocused: Bool
    let offlineSince: Date?
    /// "live ›" / "‹ live" when this cam is the offline-recovery target.
    let liveNeighborHint: String?

    private var isOffline: Bool { camera.url == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            nameLine
            if let subLabel {
                Text(subLabel)
                    .tv(22)
                    .foregroundStyle(TVInk.inactive)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var nameLine: some View {
        if let liveNeighborHint {
            Text("\(camera.name) · \(liveNeighborHint)")
                .tv(26, .extraBold)
                .foregroundStyle(TVInk.sand)
                .lineLimit(1)
        } else if isActive {
            Text(camera.name)
                .tv(28, .extraBold)
                .strikethrough(isOffline)
                .foregroundStyle(TVInk.type.opacity(isOffline ? 0.6 : 1.0))
                .lineLimit(1)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TVInk.sand.opacity(isOffline ? 0.45 : 1.0))
                        .frame(height: 4)
                }
        } else {
            Text(camera.name)
                .tv(26)
                .strikethrough(isOffline)
                .foregroundStyle(isFocused ? TVInk.type.opacity(0.9) : TVInk.inactive)
                .lineLimit(1)
        }
    }

    private var subLabel: String? {
        guard isOffline else { return nil }
        guard let offlineSince else { return "offline right now" }
        return "offline since \(SinceFormatter.string(from: offlineSince))"
    }
}

#if DEBUG
#Preview("Strip", traits: .fixedLayout(width: 1920, height: 56)) {
    @Previewable @FocusState var focus: RootFocus?
    CamStrip(
        cameras: PreviewFixtures.cameras,
        selectedID: "nsb",
        offlineSince: ["ormond-by-the-sea": PreviewFixtures.at(12, 48)],
        focus: $focus
    )
    .background(TVSkyGround.noon.gradient)
}
#endif

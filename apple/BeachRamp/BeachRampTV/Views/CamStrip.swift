import SwiftUI
import BeachStatus

/// The 56pt cam switcher under the picture: "WATCHING" plus every cam named
/// flat — a switcher, not a stepper, so a user checking three beaches a day
/// jumps instead of cycling. Active cam wears the 4pt sand underline; focus
/// moves switch the stream live (the channel-flip pattern — no Select
/// needed). The leading label says what the band is showing for the active
/// cam (`CamMode`): "Watching live" for real video, "Watching stills" when
/// it's the YouTube thumbnail, not motion. That's the only indicator; the
/// names stay one line so the row lines up (2026-11-23: per-name sub-labels
/// knocked the names out of alignment on the TV). The indicator lives here,
/// not on the band, which takes no overlays. A cam with no live video and no
/// still is struck through. When the
/// *selected* cam has no live video, the nearest live neighbor is named in
/// sand with a chevron pointing the way.
struct CamStrip: View {
    let cameras: [Camera]
    let selectedID: String?
    /// The selected cam's still read black (a dead camera, not just a dead
    /// relay) — it's offline outright, still or no still.
    var selectedStillDark: Bool = false
    let focus: FocusState<RootFocus?>.Binding

    private var selectedCamera: Camera? {
        cameras.first { $0.id == selectedID } ?? cameras.first
    }

    private var selectedOffline: Bool {
        selectedCamera.map { !$0.hasLiveVideo } ?? false
    }

    /// "Watching live" / "Watching stills" / plain "Watching". Only the mode
    /// word takes color: LIVE in sand (the strip's live color, as in the
    /// "live ›" pointer; red stays closed-only), STILLS in full white, both
    /// standing out from the muted "Watching".
    private var watchingLabel: Text {
        switch CamMode.of(selectedCamera, stillDead: selectedStillDark) {
        case .live: Text("Watching ") + Text("live").foregroundStyle(TVInk.sand)
        case .still: Text("Watching ") + Text("stills").foregroundStyle(TVInk.type)
        case .offline: Text("Watching")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            watchingLabel
                .tvLabel()
                .fixedSize()
                .accessibilityIdentifier("camStrip.watching")

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
                            mode: CamMode.of(camera, stillDead: camera.id == selectedCamera?.id && selectedStillDark),
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
        guard selectedOffline, camera.hasLiveVideo,
              let selected = selectedCamera,
              let selectedIdx = cameras.firstIndex(where: { $0.id == selected.id }),
              let camIdx = cameras.firstIndex(where: { $0.id == camera.id })
        else { return nil }

        let liveIndices = cameras.indices.filter { cameras[$0].hasLiveVideo }
        guard let nearest = liveIndices.min(by: {
            abs($0 - selectedIdx) < abs($1 - selectedIdx)
        }), nearest == camIdx else { return nil }

        return camIdx > selectedIdx ? "live ›" : "‹ live"
    }
}

/// One cam name, always a single line. Active = 28/extraBold + 4pt sand
/// underline; inactive = 26 at 50%; focus brightens; no live video and no
/// still = struck through.
private struct CamStripName: View {
    let camera: Camera
    let isActive: Bool
    let isFocused: Bool
    /// What this cam would show (a dead still is only known for the selected
    /// cam; others read `.still` until watched).
    let mode: CamMode
    /// "live ›" / "‹ live" when this cam is the offline-recovery target.
    let liveNeighborHint: String?

    private var isOffline: Bool { mode == .offline }

    var body: some View {
        nameLine
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
}

#if DEBUG
// Fixtures: Ponce Inlet is relay-dark with a still ("still photo"),
// Ormond-By-The-Sea has neither (struck through).
#Preview("Strip", traits: .fixedLayout(width: 1920, height: 56)) {
    @Previewable @FocusState var focus: RootFocus?
    CamStrip(
        cameras: PreviewFixtures.cameras,
        selectedID: "nsb",
        focus: $focus
    )
    .background(TVSky.previewNoon)
}
#Preview("Watching a still", traits: .fixedLayout(width: 1920, height: 56)) {
    @Previewable @FocusState var focus: RootFocus?
    CamStrip(
        cameras: PreviewFixtures.cameras,
        selectedID: "ponce-inlet",
        focus: $focus
    )
    .background(TVSky.previewNoon)
}
#endif

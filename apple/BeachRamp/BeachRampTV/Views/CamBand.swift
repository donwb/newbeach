import SwiftUI
import BeachStatus

/// What the verdict block in the cam band renders. Overnight gets a neutral
/// bar — the headline is factual, not an alarm — so the builder's category
/// mapping is resolved to a color before it reaches the view.
struct TVVerdictDisplay: Equatable {
    let headline: String
    let subline: String
    let barColor: Color
}

/// One cell of the boxed Water/Air/Wind strip in the band's top-right.
struct WeatherCell: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// The panorama header of design v3: the cam holds the top 405pt at its true
/// aspect and carries the brand row, the weather strip, the verdict, and the
/// cam caption strip on its own bottom edge. When the selected cam is
/// offline the band falls back to the sky gradient and the caption strip
/// does the recovery itself — the dead cam is struck through and the
/// nearest live one is named in amber. No separate banner.
struct CamBand: View {
    let streamURL: URL?
    let rebuildToken: Int
    @Binding var isPlaying: Bool
    let cameras: [Camera]
    let selectedID: String?
    /// When each offline camera was first seen dark, keyed by camera id.
    let offlineSince: [String: Date]
    /// Sun below the horizon — the cam is on infrared.
    let isNight: Bool
    let verdict: TVVerdictDisplay
    let weatherCells: [WeatherCell]
    let time: String
    /// Minutes since the ramps feed last loaded, once stale. Nil = live.
    let staleMinutes: Int?
    @FocusState.Binding var focusedCamera: String?
    let onSelectCamera: (String) -> Void
    let onPlaybackFailure: () -> Void

    @Environment(\.skyPalette) private var sky

    private var selectedCamera: Camera? {
        cameras.first { $0.id == selectedID } ?? cameras.first
    }

    /// Offline only when a roster exists and its selected cam is dark — an
    /// empty roster (old server) still plays the legacy single stream.
    private var selectedOffline: Bool {
        selectedCamera.map { $0.url == nil } ?? false
    }

    var body: some View {
        ZStack {
            background
            scrim
            content
        }
        .frame(height: 405)
        .clipped()
    }

    // MARK: - Layers

    @ViewBuilder private var background: some View {
        if !selectedOffline, let streamURL {
            TVVideoPlayerView(
                url: streamURL,
                rebuildToken: rebuildToken,
                isPlaying: $isPlaying,
                onPlaybackFailure: onPlaybackFailure
            )
        } else {
            // Cam offline: the sun-phase sky stands in for the missing frame.
            sky.gradient
        }
    }

    /// Bottom-heavy gradient protecting the caption strip; a lighter wash up
    /// top keeps the brand row readable without hiding the panorama.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color(boardHex: 0x041420).opacity(0.58), location: 0),
                .init(color: Color(boardHex: 0x041420).opacity(0.10), location: 0.32),
                .init(color: Color(boardHex: 0x041420).opacity(0.38), location: 0.60),
                .init(color: Color(boardHex: 0x041420).opacity(0.88), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 0)
            verdictBlock
            captionStrip
                .padding(.top, 16)
        }
        .padding(.top, 40)
        .padding(.horizontal, 64)
        .padding(.bottom, 20)
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(alignment: .top, spacing: 40) {
            HStack(spacing: 14) {
                Circle()
                    .fill(liveDotColor)
                    .frame(width: 13, height: 13)
                Text("Beach Ramp Status")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(26 * -0.01)
                Text("Volusia County")
                    .kickerStyle(opacity: 0.6)
                    .padding(.leading, 6)
            }

            Spacer(minLength: 0)

            HStack(spacing: 22) {
                weatherStrip
                if let staleMinutes {
                    Text("Stale · \(staleMinutes) min")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(BoardColor.verdictMixed)
                }
                Text(time)
                    .font(.system(size: 32))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
    }

    private var liveDotColor: Color {
        if staleMinutes != nil { return BoardColor.verdictMixed }
        if selectedOffline { return .white.opacity(0.5) }
        return BoardColor.verdictGood
    }

    private var weatherStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(weatherCells.enumerated()), id: \.element.id) { index, cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .kickerStyle(opacity: 0.7)
                    Text(cell.value)
                        .font(.system(size: 34, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 20)
                .overlay(alignment: .trailing) {
                    if index < weatherCells.count - 1 {
                        Rectangle().fill(.white.opacity(0.22)).frame(width: 2)
                    }
                }
            }
        }
        .background(Rectangle().fill(Color(boardHex: 0x041420).opacity(0.44)))
        .overlay(Rectangle().strokeBorder(.white.opacity(0.34), lineWidth: 2))
    }

    // MARK: - Verdict

    private var verdictBlock: some View {
        HStack(alignment: .bottom, spacing: 20) {
            Rectangle()
                .fill(verdict.barColor)
                .frame(width: 20, height: 74)
            VStack(alignment: .leading, spacing: 8) {
                Text(verdict.headline)
                    .font(.system(size: 80, weight: .heavy))
                    .tracking(80 * -0.025)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !verdict.subline.isEmpty {
                    Text(verdict.subline)
                        .font(.system(size: 30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.92)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Caption strip (cam selector)

    /// All five cams, always present, in fixed geographic order (the roster
    /// runs south→north). Per-cam state nests under its own name — never a
    /// sibling in the list, which would make the strip disagree with what
    /// the remote does.
    private var captionStrip: some View {
        HStack(alignment: .top, spacing: 20) {
            Text("Watching")
                .kickerStyle(opacity: 0.6)
                .padding(.top, 4)

            HStack(alignment: .top, spacing: 26) {
                ForEach(cameras) { camera in
                    Button {
                        onSelectCamera(camera.id)
                    } label: {
                        CamCaption(
                            camera: camera,
                            isActive: camera.id == selectedCamera?.id,
                            isFocused: camera.id == focusedCamera,
                            offlineSince: offlineSince[camera.id],
                            isNight: isNight,
                            liveNeighborHint: liveNeighborHint(for: camera)
                        )
                    }
                    .buttonStyle(CoastPinButtonStyle())
                    .focused($focusedCamera, equals: camera.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("‹ › switches cam")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.34)).frame(height: 2)
        }
        .focusSection()
        .animation(.easeOut(duration: 0.15), value: focusedCamera)
    }

    /// When the selected cam is dark, its nearest live neighbor is named in
    /// amber with a chevron pointing the way. Generated from position — the
    /// order is geographic, so the live neighbor may be in either direction.
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

/// One cam name in the caption strip. Active = 26/heavy with a 4pt white
/// underline; inactive = 24 at 55%. Offline cams are struck through with an
/// "offline since" sub-label; the active cam notes infrared after dark.
private struct CamCaption: View {
    let camera: Camera
    let isActive: Bool
    let isFocused: Bool
    let offlineSince: Date?
    let isNight: Bool
    /// "live ›" / "‹ live" when this cam is the offline-recovery target.
    let liveNeighborHint: String?

    private var isOffline: Bool { camera.url == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nameLine
            if let subLabel {
                Text(subLabel)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var nameLine: some View {
        if let liveNeighborHint {
            Text("\(camera.name) · \(liveNeighborHint)")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(BoardColor.amberAccent)
                .lineLimit(1)
        } else if isActive {
            Text(camera.name)
                .font(.system(size: 26, weight: .heavy))
                .strikethrough(isOffline)
                .foregroundStyle(.white.opacity(isOffline ? 0.6 : 1.0))
                .lineLimit(1)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(isOffline ? 0.45 : 1.0))
                        .frame(height: 4)
                }
        } else {
            Text(camera.name)
                .font(.system(size: 24))
                .strikethrough(isOffline)
                .foregroundStyle(.white.opacity(isFocused ? 0.85 : 0.55))
                .lineLimit(1)
        }
    }

    private var subLabel: String? {
        if isOffline {
            guard let offlineSince else { return "offline right now" }
            return "offline since \(SinceFormatter.string(from: offlineSince))"
        }
        if isActive && isNight {
            return "infrared after dark"
        }
        return nil
    }
}

/// Button style contributing no focus chrome of its own — the caption draws
/// all of its own focus/selection state. `.plain` still paints the system's
/// frosted bulge on tvOS; a custom ButtonStyle fully replaces it.
struct CoastPinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    @Previewable @FocusState var focused: String?
    @Previewable @State var playing = false
    VStack(spacing: 0) {
        CamBand(
            streamURL: nil,
            rebuildToken: 0,
            isPlaying: $playing,
            cameras: PreviewFixtures.cameras,
            selectedID: "nsb",
            offlineSince: ["ormond-by-the-sea": PreviewFixtures.at(12, 48)],
            isNight: false,
            verdict: TVVerdictDisplay(
                headline: "All five open",
                subline: "Tide rising · high 2:56 PM · 6h 36m of light left",
                barColor: BoardColor.verdictGood
            ),
            weatherCells: [
                WeatherCell(label: "Water", value: "82°"),
                WeatherCell(label: "Air", value: "91°"),
                WeatherCell(label: "Wind", value: "SW 5"),
            ],
            time: "1:23 PM",
            staleMinutes: nil,
            focusedCamera: $focused,
            onSelectCamera: { _ in },
            onPlaybackFailure: {}
        )
        Spacer()
    }
    .background(Color(red: 0.05, green: 0.5, blue: 0.66))
    .ignoresSafeArea()
}
#endif

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

/// The panorama header, two heights one press apart (the modes handoff):
/// Cam mode gives the video its native 680pt — the tallest sharp frame the
/// 3222×680 source can fill — and Board mode settles it into the v3 405pt
/// band. The brand row, weather strip and verdict sit at identical
/// coordinates in both modes; only the bottom edge travels, with the cam
/// caption strip fixed to it. When the selected cam is offline the band
/// falls back to the sky gradient and the caption strip does the recovery
/// itself — the dead cam is struck through and the nearest live one is
/// named in amber. No separate banner.
struct CamBand: View {
    /// Cam mode: the feed's native height (source is 3222×680) — 1:1, every
    /// source pixel mapped to one display pixel, 60% of the panorama.
    /// Filling 16:9 would upscale an already-soft stream 1.59× — never.
    /// If the feed's resolution changes, this changes with it.
    static let camModeHeight: CGFloat = 680
    /// Board mode: the full source width fits 1920 at a 0.596× downscale.
    static let boardModeHeight: CGFloat = 405

    let streamURL: URL?
    let rebuildToken: Int
    @Binding var isPlaying: Bool
    let cameras: [Camera]
    let selectedID: String?
    /// When each offline camera was first seen dark, keyed by camera id.
    let offlineSince: [String: Date]
    let verdict: TVVerdictDisplay
    let weatherCells: [WeatherCell]
    let time: String
    /// Minutes since the ramps feed last loaded, once stale. Nil = live.
    let staleMinutes: Int?
    let mode: TVBoardMode
    /// Bumps when the verdict changes while Cam mode is up — the accent bar
    /// flashes once in place. A status change never opens the board.
    let flashToken: Int
    @FocusState.Binding var focusedCamera: String?
    let onSelectCamera: (String) -> Void
    let onPlaybackFailure: () -> Void
    /// Up from the caption strip with nowhere further to go — close the board.
    let onCollapse: () -> Void

    @Environment(\.skyPalette) private var sky
    @FocusState private var collapseCatcherFocused: Bool
    @State private var verdictFlash = false

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
        .frame(height: mode == .cam ? Self.camModeHeight : Self.boardModeHeight)
        .clipped()
        .onChange(of: flashToken) { _, _ in
            verdictFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.8)) { verdictFlash = false }
            }
        }
        .onChange(of: collapseCatcherFocused) { _, focused in
            if focused { onCollapse() }
        }
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

    /// Both modes' scrims stay in the tree and crossfade with the height
    /// animation. Board mode: the v3 single full-height wash. Cam mode:
    /// separate top and bottom protections with ~300pt of clear picture
    /// between the verdict and the caption strip.
    private var scrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(boardHex: 0x041420).opacity(0.58), location: 0),
                    .init(color: Color(boardHex: 0x041420).opacity(0.10), location: 0.32),
                    .init(color: Color(boardHex: 0x041420).opacity(0.38), location: 0.60),
                    .init(color: Color(boardHex: 0x041420).opacity(0.88), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(mode == .board ? 1 : 0)

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(boardHex: 0x041420).opacity(0.72), location: 0),
                        .init(color: Color(boardHex: 0x041420).opacity(0.34), location: 0.34),
                        .init(color: Color(boardHex: 0x041420).opacity(0), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 400)
                .frame(maxHeight: .infinity, alignment: .top)

                LinearGradient(
                    stops: [
                        .init(color: Color(boardHex: 0x041420).opacity(0), location: 0),
                        .init(color: Color(boardHex: 0x041420).opacity(0.30), location: 0.54),
                        .init(color: Color(boardHex: 0x041420).opacity(0.86), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 240)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .opacity(mode == .cam ? 1 : 0)
        }
    }

    /// The chrome row and verdict are top-anchored so they hold identical
    /// coordinates in both modes — the rule that makes the switch legible.
    /// Only the flexible spacer (the picture) grows and shrinks.
    private var content: some View {
        VStack(spacing: 0) {
            topRow
            verdictBlock
                .padding(.top, 40)
            Spacer(minLength: 0)
            collapseCatcher
            captionStrip
        }
        .padding(.top, 40)
        .padding(.horizontal, 64)
        .padding(.bottom, 20)
    }

    /// Invisible focus target directly above the caption strip, live only in
    /// Board mode while the strip itself has focus: an Up press from the
    /// strip has nowhere else to go, lands here, and closes the board — the
    /// same fall-through tvOS uses on the Home screen's top row. Gating on
    /// `focusedCamera` keeps launch-time initial focus off it.
    private var collapseCatcher: some View {
        Color(boardHex: 0x041420).opacity(0.02)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .focusable(mode == .board && focusedCamera != nil)
            .focused($collapseCatcherFocused)
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
                .overlay(Rectangle().fill(.white).opacity(verdictFlash ? 0.9 : 0))
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
                            liveNeighborHint: liveNeighborHint(for: camera)
                        )
                    }
                    .buttonStyle(CoastPinButtonStyle())
                    .focused($focusedCamera, equals: camera.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("‹ › cam")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)

            Text(mode == .cam ? "▾ Ramps" : "▴ Full cam")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 4)
                .padding(.leading, 20)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.34)).frame(width: 2)
                }
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
/// "offline since" sub-label.
private struct CamCaption: View {
    let camera: Camera
    let isActive: Bool
    let isFocused: Bool
    let offlineSince: Date?
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
            mode: .board,
            flashToken: 0,
            focusedCamera: $focused,
            onSelectCamera: { _ in },
            onPlaybackFailure: {},
            onCollapse: {}
        )
        Spacer()
    }
    .background(Color(red: 0.05, green: 0.5, blue: 0.66))
    .ignoresSafeArea()
}

#Preview("Cam mode") {
    @Previewable @FocusState var focused: String?
    @Previewable @State var playing = false
    VStack(spacing: 0) {
        CamBand(
            streamURL: nil,
            rebuildToken: 0,
            isPlaying: $playing,
            cameras: PreviewFixtures.cameras,
            selectedID: "nsb",
            offlineSince: [:],
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
            mode: .cam,
            flashToken: 0,
            focusedCamera: $focused,
            onSelectCamera: { _ in },
            onPlaybackFailure: {},
            onCollapse: {}
        )
        Spacer()
    }
    .background(Color(red: 0.05, green: 0.5, blue: 0.66))
    .ignoresSafeArea()
}
#endif

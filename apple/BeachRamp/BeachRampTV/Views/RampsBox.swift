import SwiftUI
import BeachStatus

/// Shared column layout for the ledger's three-column rows, so the header
/// labels and the rows can never drift apart.
enum RampRowLayout {
    static let name: CGFloat = 340
    static let now: CGFloat = 195
    static let gap: CGFloat = 20
}

/// The ramps box: a city-titled ledger sized for five rows that scrolls for
/// the rest (Daytona's twelve), windowed by index rather than a ScrollView —
/// deterministic focus, trivial scroll-thumb math, and the overflow count
/// lives in the box header ("12 · 7 below") so a shut ramp is never silently
/// below the fold (closures sort to the top upstream).
///
/// Focus here is walked manually via onMoveCommand on the header and every
/// row: Left/Right on the header cycles the city, Left/Right on a row is
/// deliberately inert (box-local rule), and Up/Down at the window edges
/// shift the window while keeping focus on the edge row.
struct RampsBox: View {
    static let visibleRows = 5

    let city: String
    let rows: [TVRampRowModel]
    @Binding var topIndex: Int
    let focus: FocusState<RootFocus?>.Binding
    /// The cam the header's Up press should land on.
    let upTargetCamID: String?
    let onCycleCity: (Int) -> Void
    let onSelect: (TVRampRowModel) -> Void
    let onActivity: () -> Void

    private var clampedTop: Int {
        max(0, min(topIndex, max(0, rows.count - Self.visibleRows)))
    }

    private var visible: [(offset: Int, row: TVRampRowModel)] {
        let top = clampedTop
        let slice = rows[top..<min(rows.count, top + Self.visibleRows)]
        return slice.enumerated().map { ($0.offset, $0.element) }
    }

    private var belowCount: Int {
        max(0, rows.count - clampedTop - Self.visibleRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    columnHeads
                    ForEach(visible, id: \.row.id) { item in
                        rampRow(item.row, visibleIndex: item.offset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if rows.count > Self.visibleRows {
                    scrollTrack
                }
            }
            .clipped()
        }
        .focusSection()
    }

    // MARK: - Header

    private var headerFocused: Bool { focus.wrappedValue == .rampsHeader }

    private var header: some View {
        Button {
            onCycleCity(1)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Ramps").tvLabel()
                Text("‹").tv(26).foregroundStyle(chevronColor)
                Text(city)
                    .tv(30, .extraBold, tracking: -0.02)
                    .foregroundStyle(TVInk.type)
                    .padding(.bottom, headerFocused ? 2 : 0)
                    .overlay(alignment: .bottom) {
                        if headerFocused {
                            Rectangle().fill(TVInk.sand).frame(height: 4)
                        }
                    }
                Text("›").tv(26).foregroundStyle(chevronColor)
                if belowCount > 0 {
                    Text("\(rows.count) · \(belowCount) below").tvLabel()
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(BareButtonStyle())
        .focused(focus, equals: .rampsHeader)
        .accessibilityIdentifier("rampsHeader")
        .accessibilityValue(city)
        .onMoveCommand { direction in
            switch direction {
            case .left: onCycleCity(-1)
            case .right: onCycleCity(1)
            case .up:
                if let upTargetCamID { focus.wrappedValue = .cam(upTargetCamID) }
            case .down:
                if let first = visible.first { focus.wrappedValue = .ramp(first.row.id) }
            @unknown default: break
            }
            onActivity()
        }
    }

    private var chevronColor: Color {
        headerFocused ? TVInk.sand : TVInk.inactive
    }

    // MARK: - Rows

    private var columnHeads: some View {
        HStack(spacing: RampRowLayout.gap) {
            Text("Ramp").tvLabel()
                .frame(width: RampRowLayout.name, alignment: .leading)
            Text("Now").tvLabel()
                .frame(width: RampRowLayout.now, alignment: .leading)
            Text("Next").tvLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
    }

    private func rampRow(_ row: TVRampRowModel, visibleIndex: Int) -> some View {
        let isFocused = focus.wrappedValue == .ramp(row.id)
        return Button {
            onSelect(row)
        } label: {
            HStack(spacing: RampRowLayout.gap) {
                Text(row.name)
                    .tv(32, .semiBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(TVInk.type)
                    .frame(width: RampRowLayout.name, alignment: .leading)
                Text(row.nowLabel)
                    .tv(26, row.isClosed ? .bold : .semiBold)
                    .lineLimit(1)
                    .foregroundStyle(row.isClosed ? TVInk.closed : TVInk.type)
                    .frame(width: RampRowLayout.now, alignment: .leading)
                Text(row.nextLabel ?? "—")
                    .tv(26)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(TVInk.typeDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                if isFocused {
                    Rectangle().fill(TVInk.sand).frame(width: 6)
                }
            }
            .background(Rectangle().fill(TVInk.type.opacity(isFocused ? 0.08 : 0)))
            .overlay(alignment: .top) {
                Rectangle().fill(TVInk.ruleHair).frame(height: 1)
            }
        }
        .buttonStyle(BareButtonStyle())
        .focused(focus, equals: .ramp(row.id))
        .accessibilityIdentifier("rampRow.\(row.id)")
        .onMoveCommand { direction in
            move(direction, from: visibleIndex)
            onActivity()
        }
    }

    /// The manual walk. Left/Right are inert on rows by design; Up/Down at
    /// the window edges shift the window and keep focus on the edge row —
    /// deferred a runloop so the newly-windowed row exists before focus
    /// lands on it.
    private func move(_ direction: MoveCommandDirection, from visibleIndex: Int) {
        let top = clampedTop
        switch direction {
        case .up:
            if visibleIndex > 0 {
                focus.wrappedValue = .ramp(rows[top + visibleIndex - 1].id)
            } else if top > 0 {
                topIndex = top - 1
                let target = rows[top - 1].id
                DispatchQueue.main.async { focus.wrappedValue = .ramp(target) }
            } else {
                focus.wrappedValue = .rampsHeader
            }
        case .down:
            let absolute = top + visibleIndex
            if visibleIndex < Self.visibleRows - 1, absolute + 1 < rows.count {
                focus.wrappedValue = .ramp(rows[absolute + 1].id)
            } else if absolute + 1 < rows.count {
                topIndex = top + 1
                let target = rows[absolute + 1].id
                DispatchQueue.main.async { focus.wrappedValue = .ramp(target) }
            }
        case .left, .right:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Scroll track

    private var scrollTrack: some View {
        GeometryReader { geo in
            let thumbHeight = geo.size.height * CGFloat(Self.visibleRows) / CGFloat(rows.count)
            let travel = geo.size.height - thumbHeight
            let denominator = CGFloat(max(1, rows.count - Self.visibleRows))
            let offset = travel * CGFloat(clampedTop) / denominator
            ZStack(alignment: .top) {
                Rectangle().fill(TVInk.track)
                Rectangle()
                    .fill(TVInk.sand)
                    .frame(height: thumbHeight)
                    .offset(y: offset)
            }
        }
        .frame(width: 6)
        .padding(.leading, 28)
        .animation(.easeOut(duration: 0.2), value: clampedTop)
    }
}

/// The overnight variant of the left box: one line per city, since per-ramp
/// detail has nothing to say after the gates close. Not focusable — the cam
/// strip and the outlook button are the night's controls.
struct OvernightCitiesBox: View {
    let lines: [TVOvernightCityLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Overnight").tvLabel()
                Text("All cities")
                    .tv(30, .extraBold, tracking: -0.02)
                    .foregroundStyle(TVInk.type)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)
            HStack(spacing: RampRowLayout.gap) {
                Text("City").tvLabel()
                    .frame(width: RampRowLayout.name, alignment: .leading)
                Text("Now").tvLabel()
                    .frame(width: RampRowLayout.now, alignment: .leading)
                Text("Next").tvLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 8)
            ForEach(lines) { line in
                HStack(spacing: RampRowLayout.gap) {
                    Text(line.city)
                        .tv(32, .semiBold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(TVInk.type)
                        .frame(width: RampRowLayout.name, alignment: .leading)
                    Text(line.closedLabel)
                        .tv(26, .bold)
                        .foregroundStyle(TVInk.closed)
                        .frame(width: RampRowLayout.now, alignment: .leading)
                    Text(line.reopenLabel)
                        .tv(26)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(TVInk.typeDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) {
                    Rectangle().fill(TVInk.ruleHair).frame(height: 1)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Five rows", traits: .fixedLayout(width: 990, height: 420)) {
    @Previewable @FocusState var focus: RootFocus?
    @Previewable @State var top = 0
    RampsBox(
        city: "New Smyrna Beach",
        rows: PreviewFixtures.nsbRows,
        topIndex: $top,
        focus: $focus,
        upTargetCamID: "nsb",
        onCycleCity: { _ in },
        onSelect: { _ in },
        onActivity: {}
    )
    .padding(40)
    .background(TVSky.previewNoon)
}

#Preview("Twelve rows, windowed", traits: .fixedLayout(width: 990, height: 420)) {
    @Previewable @FocusState var focus: RootFocus?
    @Previewable @State var top = 0
    RampsBox(
        city: "Daytona Beach",
        rows: PreviewFixtures.daytonaRows,
        topIndex: $top,
        focus: $focus,
        upTargetCamID: "nsb",
        onCycleCity: { _ in },
        onSelect: { _ in },
        onActivity: {}
    )
    .padding(40)
    .background(TVSky.previewNoon)
}

#Preview("Overnight", traits: .fixedLayout(width: 990, height: 420)) {
    OvernightCitiesBox(lines: PreviewFixtures.overnightLines)
        .padding(40)
        .background(TVSky.previewNight)
}
#endif

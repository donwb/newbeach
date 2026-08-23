import SwiftUI
import BeachStatus

/// The 574pt resting ledger: the verdict row over the two boxes. All copy in
/// the verdict row is server-built and rendered verbatim; the accent bar is
/// the across-the-room signal (sand = all open, red = something is shut,
/// muted = overnight).
struct LedgerView: View {
    let verdict: TVVerdictModel
    /// Bumps when a status change updates the verdict in place — the bar
    /// flashes once. Never opens anything, never steals focus.
    let flashToken: Int
    /// Today's tide, drawn small beside the verdict with a now-line. Nil
    /// (chart fetch failed) leaves the row all type, as before.
    let tideChart: TideChartData?

    let city: String
    let rows: [TVRampRowModel]
    @Binding var topIndex: Int
    let surf: TVSurfBoxModel
    let weekend: [TVWeekendSlot]

    let focus: FocusState<RootFocus?>.Binding
    let upTargetCamID: String?
    let onCycleCity: (Int) -> Void
    let onSelect: (TVRampRowModel) -> Void
    let onActivity: () -> Void

    @State private var flash = false

    /// Width of the ramps column (incl. its 48pt trailing gutter) — the
    /// divider the verdict row's tide wave aligns to at rest.
    static let columnSplit: CGFloat = 985

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verdictRow
            boxes
        }
        .padding(EdgeInsets(top: 22, leading: TVMetrics.sidePad,
                            bottom: 34, trailing: TVMetrics.sidePad))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: flashToken) { _, _ in
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.8)) { flash = false }
            }
        }
    }

    /// The verdict copy on the left, today's tide on the right. At rest the
    /// wave's left edge sits exactly where the surf/weekend column below
    /// starts (`columnSplit` + the 48pt gutter); verdict copy that outgrows
    /// the split pushes the wave over and it compresses, down to a 220pt
    /// floor before the type itself starts scaling.
    private var verdictRow: some View {
        HStack(alignment: .center, spacing: 48) {
            HStack(alignment: .center, spacing: 22) {
                Rectangle()
                    .fill(verdict.barColor)
                    .overlay(Rectangle().fill(TVInk.type).opacity(flash ? 0.9 : 0))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 10) {
                    Text(verdict.headline)
                        .tv(84, .extraBold, tracking: -0.035)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(TVInk.type)
                        .accessibilityIdentifier("verdictHeadline")
                    if !verdict.detail.isEmpty {
                        Text(verdict.detail)
                            .tv(28)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(TVInk.typeMuted)
                    }
                }
            }
            .layoutPriority(1)
            .frame(minWidth: Self.columnSplit, alignment: .leading)

            verdictTideWave
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var verdictTideWave: some View {
        let range = Self.todayRange
        let points = tideChart.map { TideCurve.points(extremes: $0.highLow, in: range) } ?? []
        if points.isEmpty {
            Spacer(minLength: 0)
        } else {
            TideCurveShapeView(
                points: points,
                range: range,
                height: 128,
                strokeWidth: 3,
                strokeColor: TVInk.type.opacity(0.8),
                fillColor: TVInk.type.opacity(0.10),
                nowLineColor: TVInk.sand
            )
            .frame(minWidth: 220, maxWidth: .infinity)
            .accessibilityIdentifier("verdictTideWave")
        }
    }

    /// Midnight to midnight, Eastern — the same day the detail surface draws.
    private static var todayRange: ClosedRange<Date> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = cal.startOfDay(for: Date())
        return start...cal.date(byAdding: .day, value: 1, to: start)!
    }

    private var boxes: some View {
        HStack(alignment: .top, spacing: 0) {
            RampsBox(
                city: city,
                rows: rows,
                topIndex: $topIndex,
                focus: focus,
                upTargetCamID: upTargetCamID,
                onCycleCity: onCycleCity,
                onSelect: onSelect,
                onActivity: onActivity
            )
            .padding(.top, 10)
            .padding(.trailing, 48)
            .frame(width: Self.columnSplit, alignment: .topLeading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(TVInk.rule).frame(width: 2)
            }

            SurfWeekendBox(surf: surf, weekend: weekend)
                .padding(.top, 10)
                .padding(.leading, 48)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .overlay(alignment: .top) {
            Rectangle().fill(TVInk.rule).frame(height: 2)
        }
    }
}

#if DEBUG
#Preview("Resting", traits: .fixedLayout(width: 1920, height: 574)) {
    @Previewable @FocusState var focus: RootFocus?
    @Previewable @State var top = 0
    LedgerView(
        verdict: TVVerdictModel(
            headline: "All five open",
            detail: "Two could shut on the ~3pm high · first around 3",
            barColor: TVInk.sand
        ),
        flashToken: 0,
        tideChart: PreviewFixtures.tideChart,
        city: "New Smyrna Beach",
        rows: PreviewFixtures.nsbRows,
        topIndex: $top,
        surf: TVSurfBoxModel(
            windowLabel: "Now",
            headline: "Pretty much flat out there",
            detail: "Knee-high · 6s · rip risk low · buoy read 40 min ago",
            hasRead: true
        ),
        weekend: [
            TVWeekendSlot(id: "2026-08-22", dayName: "Saturday",
                          headline: "Best 9am–1pm", metrics: "93° · mid-day close potential"),
            TVWeekendSlot(id: "2026-08-23", dayName: "Sunday",
                          headline: "Wide open all day", metrics: "91° · clear all day"),
        ],
        focus: $focus,
        upTargetCamID: "nsb",
        onCycleCity: { _ in },
        onSelect: { _ in },
        onActivity: {}
    )
    .background(TVSky.previewNoon)
}

#Preview("Something shut", traits: .fixedLayout(width: 1920, height: 574)) {
    @Previewable @FocusState var focus: RootFocus?
    @Previewable @State var top = 0
    LedgerView(
        verdict: TVVerdictModel(
            headline: "Ten of twelve open",
            detail: "Harvey Ave and Van Ave closed for the tide since 11:40am · six more could shut on the ~3pm high",
            barColor: TVInk.closed
        ),
        flashToken: 0,
        tideChart: PreviewFixtures.tideChart,
        city: "Daytona Beach",
        rows: PreviewFixtures.daytonaRows,
        topIndex: $top,
        surf: TVSurfBoxModel(
            windowLabel: "Now",
            headline: "Pretty much flat out there",
            detail: "Knee-high · 6s · rip risk low",
            hasRead: true
        ),
        weekend: [
            TVWeekendSlot(id: "2026-08-22", dayName: "Saturday",
                          headline: "Best 9am–1pm", metrics: "93° · mid-day close potential"),
            TVWeekendSlot(id: "2026-08-23", dayName: "Sunday",
                          headline: "Wide open all day", metrics: "91° · clear all day"),
        ],
        focus: $focus,
        upTargetCamID: "nsb",
        onCycleCity: { _ in },
        onSelect: { _ in },
        onActivity: {}
    )
    .background(TVSky.previewNoon)
}

#Preview("Overnight", traits: .fixedLayout(width: 1920, height: 574)) {
    @Previewable @FocusState var focus: RootFocus?
    @Previewable @State var top = 0
    LedgerView(
        verdict: TVVerdictModel(
            headline: "Driving is done for the day",
            detail: "Every ramp reopens around 8am, once ramps are cleared for turtles",
            barColor: TVInk.barMuted
        ),
        flashToken: 0,
        tideChart: PreviewFixtures.tideChart,
        city: "New Smyrna Beach",
        rows: PreviewFixtures.overnightRows,
        topIndex: $top,
        surf: TVSurfBoxModel(
            windowLabel: "Now",
            headline: "No surf read right now",
            detail: "Buoy is quiet — no recent report",
            hasRead: false
        ),
        weekend: [
            TVWeekendSlot(id: "2026-08-22", dayName: "Saturday",
                          headline: "Best 9am–1pm", metrics: "93° · mid-day close potential"),
            TVWeekendSlot(id: "2026-08-23", dayName: "Sunday",
                          headline: "Wide open all day", metrics: "91° · clear all day"),
        ],
        focus: $focus,
        upTargetCamID: "nsb",
        onCycleCity: { _ in },
        onSelect: { _ in },
        onActivity: {}
    )
    .background(TVSky.previewNight)
}
#endif

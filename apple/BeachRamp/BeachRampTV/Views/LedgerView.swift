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

    let city: String
    let rows: [TVRampRowModel]
    @Binding var topIndex: Int
    let overnightLines: [TVOvernightCityLine]?
    let surf: TVSurfBoxModel
    let weekend: [TVWeekendSlot]

    let focus: FocusState<RootFocus?>.Binding
    let upTargetCamID: String?
    let onCycleCity: (Int) -> Void
    let onSelect: (TVRampRowModel) -> Void
    let onActivity: () -> Void

    @State private var flash = false

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

    private var verdictRow: some View {
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
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var boxes: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if let overnightLines {
                    OvernightCitiesBox(lines: overnightLines)
                } else {
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
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 48)
            .frame(width: 985, alignment: .topLeading)
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
        city: "New Smyrna Beach",
        rows: PreviewFixtures.nsbRows,
        topIndex: $top,
        overnightLines: nil,
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
        city: "Daytona Beach",
        rows: PreviewFixtures.daytonaRows,
        topIndex: $top,
        overnightLines: nil,
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
        city: "New Smyrna Beach",
        rows: [],
        topIndex: $top,
        overnightLines: PreviewFixtures.overnightLines,
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

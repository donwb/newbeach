import SwiftUI
import BeachStatus

/// The Beach outlook pull surface: the week ahead as one table — Day / High
/// / Rain / Surf / Best window / Closure risk. The closure-risk column is
/// deliberately vague about which ramps: this far out the tide is knowable
/// and the individual gates are not, so it warns about the beach day and
/// never names a ramp (server-enforced). Today wears the sand marker; the
/// worst case ("All-day close risk") is the one red thing here.
struct BeachOutlookSurface: View {
    let city: String
    let rows: [TVOutlookDayRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 40) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    Text("Beach outlook")
                        .tv(52, .extraBold, tracking: -0.03)
                        .foregroundStyle(TVInk.type)
                    Text("\(city) · \(rows.count) days").tvLabel()
                }
                Spacer(minLength: 0)
                SurfaceBackHint()
            }

            VStack(alignment: .leading, spacing: 0) {
                headRow
                ForEach(rows) { row in
                    dayRow(row)
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(TVInk.rule).frame(height: 2)
            }

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 24, leading: TVMetrics.sidePad,
                            bottom: 36, trailing: TVMetrics.sidePad))
    }

    // Column widths over the 1792pt content span, from the handoff's
    // 1fr / .45 / .45 / .95 / .95 / 1.5 template with 20pt gaps.
    private let colDay: CGFloat = 300
    private let colHigh: CGFloat = 135
    private let colRain: CGFloat = 135
    private let colSurf: CGFloat = 285
    private let colWindow: CGFloat = 285

    private var headRow: some View {
        HStack(spacing: 20) {
            Text("Day").tvLabel().frame(width: colDay, alignment: .leading)
            Text("High").tvLabel().frame(width: colHigh, alignment: .leading)
            Text("Rain").tvLabel().frame(width: colRain, alignment: .leading)
            Text("Surf").tvLabel().frame(width: colSurf, alignment: .leading)
            Text("Best window").tvLabel().frame(width: colWindow, alignment: .leading)
            Text("Closure risk").tvLabel().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
    }

    private func dayRow(_ row: TVOutlookDayRow) -> some View {
        HStack(spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if row.isToday {
                    Rectangle().fill(TVInk.sand).frame(width: 8, height: 26)
                }
                Text(row.day)
                    .tv(32, .semiBold)
                    .foregroundStyle(TVInk.type)
            }
            .frame(width: colDay, alignment: .leading)
            Text(row.high)
                .tv(26, .semiBold).monospacedDigit()
                .foregroundStyle(TVInk.type)
                .frame(width: colHigh, alignment: .leading)
            Text(row.rain)
                .tv(26).monospacedDigit()
                .foregroundStyle(TVInk.typeDim)
                .frame(width: colRain, alignment: .leading)
            Text(row.surf)
                .tv(26, .semiBold)
                .foregroundStyle(TVInk.type)
                .frame(width: colSurf, alignment: .leading)
            Text(row.bestWindow)
                .tv(26, .semiBold).monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(TVInk.type)
                .frame(width: colWindow, alignment: .leading)
            Text(row.closureRisk)
                .tv(26, row.isWorstRisk ? .bold : .regular)
                .lineLimit(1)
                .foregroundStyle(row.isWorstRisk ? TVInk.closed : TVInk.typeDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(TVInk.ruleHair).frame(height: 1)
        }
    }
}

#if DEBUG
#Preview("Outlook", traits: .fixedLayout(width: 1920, height: 630)) {
    BeachOutlookSurface(city: "New Smyrna Beach", rows: PreviewFixtures.outlookRows)
        .background(TVInk.ground)
}
#endif

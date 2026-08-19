import SwiftUI
import BeachStatus

/// The beach forecast overlay of design v3 — opens from the weekend panels.
/// Seven-day table: verdict mark first, the server's headline verbatim, the
/// weather facts on the right, and a "No call" row for days past the NWS
/// horizon. Every string is the server's; the client never words its own
/// predictions.
struct ForecastOverlay: View {
    let city: String
    let weekend: WeekendOutlook
    let onClose: () -> Void

    @FocusState private var focused: Bool

    private static let eastern = TimeZone(identifier: "America/New_York")!

    /// Today's Eastern date in the server's "2026-08-22" label format.
    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Self.eastern
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        ZStack {
            BoardColor.overlayField
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(.white.opacity(0.4)).frame(height: 2)
                    .padding(.top, 22)
                columnHeader
                dayRows
                footer
            }
            .padding(.top, 48)
            .padding(.horizontal, 80)
            .padding(.bottom, 42)
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Beach forecast · \(city)")
                    .kickerStyle(opacity: 0.65)
                Text(weekend.headline)
                    .font(.system(size: 54, weight: .heavy))
                    .tracking(54 * -0.02)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Text("Press Menu to close")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var columnHeader: some View {
        ForecastRow(
            day: Text("Day"), call: Text("Call"),
            expect: Text("What to expect"),
            facts: Text("High · rain · wind")
        )
        .font(.system(size: 22, weight: .semibold))
        .tracking(22 * 0.08)
        .textCase(.uppercase)
        .foregroundStyle(.white.opacity(0.6))
        .padding(.vertical, 14)
    }

    // Rows share the space between the header and the footer evenly, so the
    // table always fills the panel whether the server sent six days or seven.
    private var dayRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(weekend.days.enumerated()), id: \.element.date) { index, day in
                DayRow(day: day, isToday: day.date == todayLabel,
                       isLast: index == weekend.days.count - 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Tide closures are always possible, never promised — times are approximate.")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text("NWS api.weather.gov · NOAA tide predictions · generated \(SinceFormatter.clock(weekend.generatedAt))")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 20)
    }
}

/// The table's shared four-column frame: 210 / 150 / flexible / 300, 28 gap.
private struct ForecastRow<D: View, C: View, E: View, F: View>: View {
    let day: D
    let call: C
    let expect: E
    let facts: F

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            day.frame(width: 210, alignment: .leading)
            call.frame(width: 150, alignment: .leading)
            expect.frame(maxWidth: .infinity, alignment: .leading)
            facts.frame(width: 300, alignment: .trailing)
        }
    }
}

private struct DayRow: View {
    let day: WeekendDay
    let isToday: Bool
    let isLast: Bool

    var body: some View {
        ForecastRow(
            day: dayCell,
            call: callCell,
            expect: Text(day.headline)
                .font(.system(size: 30))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(isNoCall ? 0.8 : 1.0)),
            facts: Text(factsLine)
                .font(.system(size: 28))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(factsLine == "—" ? 0.5 : 0.85))
        )
        .padding(.vertical, 8)
        .background(isToday ? Color.white.opacity(0.05) : .clear)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            if isLast {
                Rectangle().fill(.white.opacity(0.4)).frame(height: 2)
            }
        }
    }

    private var isNoCall: Bool { day.verdict == "no_call" }

    private var dayCell: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isToday ? "Today" : day.weekday)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(isToday ? day.weekday : monthDay)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.leading, 14)
    }

    private var callCell: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(BoardColor.verdictMark(for: day.verdict))
                .frame(width: 14, height: 30)
            Text(day.verdictLabel)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white.opacity(isNoCall ? 0.8 : 1.0))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// "Aug 22" from the server's "2026-08-22" date label.
    private var monthDay: String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone(identifier: "America/New_York")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: day.date) else { return day.date }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.timeZone = inFmt.timeZone
        outFmt.dateFormat = "MMM d"
        return outFmt.string(from: date)
    }

    /// "91° · 10% · SW 5" — em dash when the day has no weather call.
    private var factsLine: String {
        var parts: [String] = []
        if let high = day.highTempF {
            parts.append("\(Int(high.rounded()))°")
        }
        if let rain = day.rainChancePct {
            parts.append("\(Int(rain.rounded()))%")
        }
        if let wind = day.windLabel {
            parts.append(wind.replacingOccurrences(of: " mph", with: ""))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// "Great", "No call" — display casing for verdict words.
extension WeekendDay {
    var verdictLabel: String {
        verdictDisplay.prefix(1).uppercased() + verdictDisplay.dropFirst()
    }
}

#if DEBUG
#Preview {
    ForecastOverlay(city: "New Smyrna Beach",
                    weekend: PreviewFixtures.weekend,
                    onClose: {})
}
#endif

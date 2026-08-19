import SwiftUI
import BeachStatus

/// TV-side read of a weekend verdict. The vocabulary is the server's
/// (`great|good|mixed|tough|no_call`) — this only maps it onto the board's
/// status colors; unknown future values fall through to the muted look.
extension WeekendDay {
    /// The board status category whose color carries this verdict, or nil
    /// for no_call / unknown (rendered muted, never colored).
    var verdictCategory: StatusCategory? {
        switch verdict {
        case "great", "good": return .open
        case "mixed": return .limited
        case "tough": return .closed
        default: return nil
        }
    }

    /// "Great", "No call" — display casing for tile faces and pills.
    var verdictLabel: String {
        verdictDisplay.prefix(1).uppercased() + verdictDisplay.dropFirst()
    }
}

/// Full-screen outlook: the week's one-line answer up top, today's surf
/// read, then the next six days as columns — verdict pill, the day's story,
/// the best stretch, and the weather facts. Every string is the server's;
/// the client never words its own predictions.
struct OutlookOverlay: View {
    let weekend: WeekendOutlook
    /// Today's full surf line — the tile face may truncate it, this never does.
    let surfLine: String?
    let onClose: () -> Void

    var body: some View {
        OverlayScaffold(
            kicker: "When should I go?",
            title: weekend.headline,
            titleSize: 56,
            footnote: footnote,
            onClose: onClose
        ) {
            if let surfLine {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text("Surf today")
                        .kickerStyle()
                    Text(surfLine)
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 26)
            }

            HStack(alignment: .top, spacing: 24) {
                ForEach(weekend.days, id: \.date) { day in
                    DayColumn(day: day)
                }
            }
            .padding(.top, surfLine == nil ? 34 : 30)
        }
    }

    private var footnote: String {
        "Tide predictions + NWS forecast · updated \(SinceFormatter.clock(weekend.generatedAt)) · press Menu to close"
    }
}

/// One graded day. Weekend days get the stronger top rule and full-ink
/// weekday, mirroring the website's weekend section.
private struct DayColumn: View {
    let day: WeekendDay

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(day.isWeekend ? BoardColor.ruleStrong : BoardColor.ruleLight)
                .frame(height: 2)

            Text(day.weekdayShort)
                .kickerStyle(opacity: day.isWeekend ? 1.0 : 0.65)

            verdictPill

            Text(day.headline)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let why = day.why {
                Text(why)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The web's dedup rule: skip the window line when the headline
            // already names it.
            if let window = day.bestWindow, !day.headline.contains(window.label) {
                Text("Best stretch \(window.label)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !factsLine.isEmpty {
                Text(factsLine)
                    .font(.system(size: 21))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var verdictPill: some View {
        Text(day.verdictLabel)
            .font(.system(size: 22, weight: .bold))
            .tracking(22 * 0.06)
            .textCase(.uppercase)
            .foregroundStyle(pillInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Rectangle().fill(pillFill))
    }

    /// Overlays render above the night scrim as opaque designed fields, so
    /// they use raw status colors, not the sky-muted ones (SkyPalette rule).
    private var pillFill: Color {
        day.verdictCategory?.statusColor ?? BoardColor.chipFill
    }

    private var pillInk: Color {
        switch day.verdictCategory {
        case .limited: return BoardColor.limitedInk
        case .open, .closed: return .white
        case nil: return .white.opacity(0.75)
        }
    }

    /// "93° (feels 105°) · 40% rain · ENE 12 mph"
    private var factsLine: String {
        var parts: [String] = []
        if let high = day.highTempF {
            var temp = "\(Int(high.rounded()))°"
            if let feels = day.feelsLikeF {
                temp += " (feels \(Int(feels.rounded()))°)"
            }
            parts.append(temp)
        }
        if let rain = day.rainChancePct {
            parts.append("\(Int(rain.rounded()))% rain")
        }
        if let wind = day.windLabel {
            parts.append(wind)
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview {
    OutlookOverlay(weekend: PreviewFixtures.weekend,
                   surfLine: "Clean chest-high — worth a paddle",
                   onClose: {})
}
#endif

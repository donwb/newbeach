import SwiftUI
import BeachStatus

/// "When should I go?" — the server's weekend outlook, one row per day.
/// Every string is server copy rendered verbatim (headline, why, window
/// label, wind label); the only client mapping is verdict → pill color,
/// the same contract the web and tvOS use. Weekend days carry the accent
/// rule so Saturday and Sunday read first at a glance.
struct WeekendSectionView: View {
    let weekend: WeekendOutlook?
    @Environment(\.ground) private var ground

    var body: some View {
        if let weekend, !weekend.days.isEmpty {
            let t = ground.tokens
            VStack(alignment: .leading, spacing: 10) {
                Text("When should I go?".uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(t.ink2)
                if !weekend.headline.isEmpty {
                    Text(weekend.headline)
                        .font(.archivo(17, weight: .extraBold))
                        .tracking(17 * ArchivoTracking.rampName)
                        .foregroundStyle(t.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(weekend.days, id: \.date) { day in
                        WeekendDayRow(day: day, isToday: day.date == Self.todayDateLabel())
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(t.rule2).frame(height: 1)
                            }
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Today's Eastern calendar date in the server's "2026-08-22" form.
    static func todayDateLabel(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = SinceFormatter.eastern
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}

/// One graded day: weekday + verdict pill on top, the headline, the
/// justification and best window when the headline doesn't already carry
/// them, and the day's numbers underneath.
struct WeekendDayRow: View {
    let day: WeekendDay
    var isToday = false
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(day.isWeekend ? t.accent : .clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text((isToday ? "Today" : day.weekdayShort).uppercased())
                        .font(.archivo(11, weight: .bold))
                        .tracking(11 * ArchivoTracking.kicker)
                        .foregroundStyle(day.isWeekend ? t.ink : t.ink2)
                    pill
                    Spacer(minLength: 0)
                }
                Text(day.headline)
                    .font(.archivo(15, weight: .extraBold))
                    .foregroundStyle(t.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = day.why, !why.isEmpty {
                    Text(why)
                        .font(.archivo(12))
                        .foregroundStyle(t.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let window = day.bestWindow?.label, !day.headline.contains(window) {
                    Text("Best stretch ~\(window)")
                        .font(.archivo(12))
                        .italic()
                        .foregroundStyle(t.ink2)
                }
                if let attrs {
                    Text(attrs)
                        .font(.archivo(11))
                        .monospacedDigit()
                        .foregroundStyle(t.ink2)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// The verdict word on its color — solid field, radius 0, like the
    /// status marks. Unknown server values get the muted field.
    private var pill: some View {
        let (fill, ink) = pillColors
        return Text(day.verdictDisplay.uppercased())
            .font(.archivo(9, weight: .bold))
            .tracking(9 * ArchivoTracking.kicker)
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(fill)
    }

    private var pillColors: (Color, Color) {
        let isDay = ground.isDay
        switch day.verdict {
        case "great":
            return (StatusField.field(for: .open, isDay: isDay).mark, isDay ? .white : Color(red: 0x04 / 255, green: 0x18 / 255, blue: 0x22 / 255))
        case "good":
            return (StatusField.field(for: .open, isDay: isDay).mark.opacity(0.75), isDay ? .white : Color(red: 0x04 / 255, green: 0x18 / 255, blue: 0x22 / 255))
        case "mixed":
            let f = StatusField.field(for: .limited, isDay: isDay)
            return (f.fill, f.text)
        case "tough":
            let f = StatusField.field(for: .closed, isDay: isDay)
            return (f.fill, f.text)
        default:
            return (ground.tokens.ink2, isDay ? .white : Color(red: 0x04 / 255, green: 0x18 / 255, blue: 0x22 / 255))
        }
    }

    /// "91° (feels 98°) · 40% rain · Breezy onshore" — same assembly as the web.
    private var attrs: String? {
        var parts: [String] = []
        if let high = day.highTempF {
            var temp = "\(Int(high.rounded()))°"
            if let feels = day.feelsLikeF { temp += " (feels \(Int(feels.rounded()))°)" }
            parts.append(temp)
        }
        if let rain = day.rainChancePct { parts.append("\(Int(rain.rounded()))% rain") }
        if let wind = day.windLabel, !wind.isEmpty { parts.append(wind) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Weekend") {
    WeekendSectionView(weekend: WeekendOutlook(
        generatedAt: Date(),
        headline: "Saturday's the day this weekend.",
        days: [
            WeekendDay(date: WeekendSectionView.todayDateLabel(), weekday: "Friday", isWeekend: false,
                       verdict: "mixed", basis: ["tide", "weather"],
                       headline: "Tide closures possible around 1:30pm",
                       why: "Afternoon high tide leans on the ramps.",
                       bestWindow: OutlookWindow(label: "8am–noon", start: Date(), end: Date()),
                       closurePressure: "some", highTempF: 91, feelsLikeF: 99,
                       rainChancePct: 40, windLabel: "Light onshore"),
            WeekendDay(date: "2099-01-02", weekday: "Saturday", isWeekend: true,
                       verdict: "great", basis: ["tide", "weather"],
                       headline: "Wide open all day", closurePressure: "none",
                       highTempF: 89, rainChancePct: 10, windLabel: "Calm"),
            WeekendDay(date: "2099-01-03", weekday: "Sunday", isWeekend: true,
                       verdict: "tough", basis: ["tide"],
                       headline: "Storms block the afternoon", why: "Tide-only read — no NWS coverage.",
                       closurePressure: "high", highTempF: 86, rainChancePct: 70),
        ]
    ))
    .padding(18)
    .environment(\.ground, GroundModel(overrideDate: Calendar.current.startOfDay(for: Date()).addingTimeInterval(13 * 3600)).state)
}
#endif

import SwiftUI
import WidgetKit
import BeachStatus

struct WatchRampWidgetView: View {
    let entry: WatchRampEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            WatchCircularView(entry: entry)
        case .accessoryCorner:
            WatchCornerView(entry: entry)
        case .accessoryInline:
            Text("\(entry.city.watchCityShort) \(entry.openCount)/\(entry.cityRamps.count) open")
                .containerBackground(for: .widget) { Color.clear }
        default:
            WatchRampCardView(entry: entry)
        }
    }
}

// MARK: - The card

/// Four circles on the Smart Stack card. Status reads from the glyph and
/// fill as well as the hue, because watch faces tint widgets to one colour:
/// open is a filled check, limited a filled bang, closed a hollow cross.
struct WatchRampCardView: View {
    let entry: WatchRampEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(entry.city.watchCityShort.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(countLine)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if entry.picks.isEmpty {
                Text("Open Beach Info to load ramps")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(entry.picks) { ramp in
                        RampCircle(ramp: ramp)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.03, green: 0.20, blue: 0.24),
                                    Color(red: 0.02, green: 0.10, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var countLine: String {
        if entry.stale { return "as of \(SinceFormatter.clock(entry.date))" }
        return "\(entry.openCount) of \(entry.cityRamps.count) open"
    }

    private var accessibilityText: String {
        let rows = entry.picks.map { "\($0.shortDisplayName) \($0.category.watchWord)" }
        return "\(entry.city): \(entry.openCount) of \(entry.cityRamps.count) open. "
            + rows.joined(separator: ", ")
    }
}

struct RampCircle: View {
    let ramp: Ramp
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: ramp.category.watchGlyph)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(renderingMode == .fullColor ? .palette : .monochrome)
                .foregroundStyle(glyphStyle, circleStyle)
                .widgetAccentable()
            Text(ramp.circleLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // Full colour: white mark on the status disc (closed stays hollow, the
    // ring in its colour). Tinted faces drop to one ink and let the glyph
    // carry the state.
    private var glyphStyle: Color {
        guard renderingMode == .fullColor else { return .primary }
        return ramp.category == .closed ? ramp.category.statusColor : .white
    }

    private var circleStyle: Color {
        renderingMode == .fullColor ? ramp.category.statusColor : .primary
    }
}

// MARK: - Faces

struct WatchCircularView: View {
    let entry: WatchRampEntry

    var body: some View {
        Gauge(value: Double(entry.openCount), in: 0...Double(max(entry.cityRamps.count, 1))) {
            Text("OPEN")
        } currentValueLabel: {
            Text("\(entry.openCount)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(Color(red: 0x29 / 255, green: 0xC9 / 255, blue: 0x7A / 255))
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel("\(entry.openCount) of \(entry.cityRamps.count) ramps open")
    }
}

struct WatchCornerView: View {
    let entry: WatchRampEntry

    var body: some View {
        Text("\(entry.openCount)")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(entry.openCount),
                      in: 0...Double(max(entry.cityRamps.count, 1))) {
                    Text("OPEN")
                } currentValueLabel: {
                    Text("\(entry.openCount)")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("\(entry.cityRamps.count)")
                }
                .tint(Color(red: 0x29 / 255, green: 0xC9 / 255, blue: 0x7A / 255))
            }
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityLabel("\(entry.openCount) of \(entry.cityRamps.count) ramps open")
    }
}

// MARK: - Helpers

extension StatusCategory {
    var watchGlyph: String {
        switch self {
        case .open: "checkmark.circle.fill"
        case .limited: "exclamationmark.circle.fill"
        case .closed: "xmark.circle"
        }
    }

    var watchWord: String {
        switch self {
        case .open: "open"
        case .limited: "limited"
        case .closed: "closed"
        }
    }
}

extension Ramp {
    /// One word under a circle: the street, not its suffix ("Beachway",
    /// "3rd", "Flagler").
    var circleLabel: String {
        shortDisplayName.split(separator: " ").first.map(String.init) ?? shortDisplayName
    }
}

extension String {
    /// City names short enough for a watch header.
    var watchCityShort: String {
        switch self {
        case "New Smyrna Beach": "New Smyrna"
        case "Daytona Beach": "Daytona"
        case "Daytona Beach Shores": "Daytona Shores"
        case "Ormond Beach": "Ormond"
        default: self
        }
    }
}

#Preview("Card", as: .accessoryRectangular) {
    WatchRampWidget()
} timeline: {
    WatchRampEntry(date: .now, city: "New Smyrna Beach",
                   cityRamps: WatchRampEntry.sampleRamps,
                   picks: Array(WatchRampEntry.sampleRamps.prefix(4)), stale: false)
}

#Preview("Circular", as: .accessoryCircular) {
    WatchRampWidget()
} timeline: {
    WatchRampEntry(date: .now, city: "New Smyrna Beach",
                   cityRamps: WatchRampEntry.sampleRamps,
                   picks: Array(WatchRampEntry.sampleRamps.prefix(4)), stale: false)
}

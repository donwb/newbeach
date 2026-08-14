import SwiftUI
import BeachStatus

/// The ramp status grid: one row of numbered tiles, status carried by the
/// tile field and a solid mark — never by tinted text. Open tiles are quiet;
/// limited and closed become solid amber/red fields so the tile that matters
/// is the only loud thing on screen.
struct RampGridView: View {
    let ramps: [Ramp]
    /// When set, the board is stale: tiles mute to 42% and their since lines
    /// become "as of {time}".
    let staleAsOf: String?

    private var columns: [GridItem] {
        if ramps.count <= 5 {
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: max(1, ramps.count))
        }
        // Cities with more ramps wrap rather than crushing names.
        return [GridItem(.adaptive(minimum: 330), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(ramps.enumerated()), id: \.element.id) { index, ramp in
                TVRampTile(ramp: ramp, index: index + 1, staleAsOf: staleAsOf)
            }
        }
    }
}

/// One ramp tile: index + name on top, status mark + since line at the bottom.
struct TVRampTile: View {
    let ramp: Ramp
    let index: Int
    let staleAsOf: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(22 * 0.08)
                    .foregroundStyle(textColor.opacity(0.65))
                Text(ramp.rampDisplayName)
                    .font(.system(size: 38, weight: .bold))
                    .tracking(38 * -0.01)
                    .lineSpacing(38 * 0.02)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(textColor)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(markColor)
                        .frame(width: 14, height: 26)
                    Text(statusText)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(textColor)
                }
                Text(sinceText)
                    .font(.system(size: 22))
                    .foregroundStyle(textColor.opacity(0.7))
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 184)
        .background(alignment: .center) {
            if hasGlow {
                // The spec's `0 0 0 6` outer glow: a dark ring separating a
                // saturated field from a saturated sky.
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .padding(-6)
            }
        }
        .background(fieldColor)
        .overlay(Rectangle().strokeBorder(borderColor, lineWidth: 2))
        .opacity(staleAsOf == nil ? 1.0 : 0.42)
    }

    // MARK: State-driven colors

    private var fieldColor: Color {
        switch ramp.category {
        case .open: BoardColor.tileFieldOpen
        case .limited: StatusCategory.limited.statusColor
        case .closed: StatusCategory.closed.statusColor
        }
    }

    private var borderColor: Color {
        switch ramp.category {
        case .open: BoardColor.tileBorderOpen
        case .limited: StatusCategory.limited.statusColor
        case .closed: StatusCategory.closed.statusColor
        }
    }

    private var textColor: Color {
        switch ramp.category {
        case .open, .closed: .white
        case .limited: BoardColor.limitedInk
        }
    }

    private var markColor: Color {
        switch ramp.category {
        case .open: StatusCategory.open.statusColor
        case .limited: BoardColor.limitedInk
        case .closed: .white
        }
    }

    private var hasGlow: Bool {
        ramp.category != .open
    }

    // MARK: Copy

    /// Board status strings, e.g. "Open", "Closed — high tide", "Entrance only".
    private var statusText: String {
        switch ramp.accessStatus.trimmingCharacters(in: .whitespaces).uppercased() {
        case "OPEN": return "Open"
        case "CLOSED": return "Closed"
        case "CLOSED FOR HIGH TIDE": return "Closed — high tide"
        case "CLOSED - AT CAPACITY": return "Closed — at capacity"
        case "CLOSED - CLEARED FOR TURTLES": return "Closed — turtles"
        case "CLOSING IN PROGRESS": return "Closing now"
        case "OPEN - ENTRANCE ONLY": return "Entrance only"
        case "4X4 ONLY": return "4x4 only"
        default:
            let phrase = ramp.accessStatus.lowercased().replacingOccurrences(of: " - ", with: " — ")
            return phrase.prefix(1).uppercased() + phrase.dropFirst()
        }
    }

    private var sinceText: String {
        if let staleAsOf {
            return "as of \(staleAsOf)"
        }
        guard let since = ramp.statusSince else { return " " }
        return "since \(SinceFormatter.string(from: since))"
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        RampGridView(ramps: PreviewFixtures.mixedRamps, staleAsOf: nil)
            .padding(.horizontal, 60)
    }
}

#Preview("Stale") {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        RampGridView(ramps: PreviewFixtures.openRamps, staleAsOf: "2:09 PM")
            .padding(.horizontal, 60)
    }
}
#endif

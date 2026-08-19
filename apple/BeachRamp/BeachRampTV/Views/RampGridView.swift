import SwiftUI
import BeachStatus

/// One ramp card's display inputs, resolved by the owner: the county ramp,
/// the v3 field state (which folds the outlook's overnight call in), and
/// the forward-looking third line.
struct TVRampCardModel: Identifiable {
    let ramp: Ramp
    let state: TVRampState
    /// Server outlook string for the third line ("could close on the ~3pm
    /// tide", "opens around 8am"). Nil falls back to the since line.
    let shortLine: String?

    var id: Int { ramp.id }
}

/// The ramp status row of design v3: five 218pt cards, status carried by the
/// card's field and a solid mark — never by tinted text. Open cards are
/// quiet ink; limited and closed become solid amber/red fields; an expected
/// overnight close is a neutral field so red keeps meaning "unplanned".
struct RampGridView: View {
    let cards: [TVRampCardModel]
    /// When set, the board is stale: cards mute to 42% and their third
    /// lines become "as of {time}".
    let staleAsOf: String?

    private var columns: [GridItem] {
        if cards.count <= 5 {
            return Array(repeating: GridItem(.flexible(), spacing: 18), count: max(1, cards.count))
        }
        // Cities with more ramps wrap rather than crushing names.
        return [GridItem(.adaptive(minimum: 330), spacing: 18)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                TVRampTile(card: card, index: index + 1, staleAsOf: staleAsOf)
            }
        }
    }
}

/// One ramp card: index + name up top, status mark + word and the outlook
/// line at the bottom.
struct TVRampTile: View {
    let card: TVRampCardModel
    let index: Int
    let staleAsOf: String?

    private var state: TVRampState { card.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(22 * 0.08)
                    .foregroundStyle(state.ink.opacity(0.6))
                Text(card.ramp.rampDisplayName)
                    .font(.system(size: 40, weight: .heavy))
                    .tracking(40 * -0.015)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(state.ink)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(state.mark)
                        .frame(width: 14, height: 26)
                    Text(statusText)
                        .font(.system(size: 30, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(state.ink)
                }
                Text(thirdLine)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(state.ink.opacity(0.78))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 218)
        .background(alignment: .center) {
            if hasGlow {
                // A dark ring separating a saturated field from the sky.
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .padding(-6)
            }
        }
        .background(state.field)
        .overlay(Rectangle().strokeBorder(state.border, lineWidth: 2))
        .opacity(staleAsOf == nil ? 1.0 : 0.42)
    }

    private var hasGlow: Bool {
        state == .limited || state == .closed
    }

    // MARK: Copy

    /// Board status strings, e.g. "Open", "Closed — high tide", "Entrance
    /// only". An overnight card always says "Closed" — the third line
    /// carries the reopen story.
    private var statusText: String {
        if state == .overnight { return "Closed" }
        switch card.ramp.accessStatus.trimmingCharacters(in: .whitespaces).uppercased() {
        case "OPEN": return "Open"
        case "CLOSED": return "Closed"
        case "CLOSED FOR HIGH TIDE": return "Closed — high tide"
        case "CLOSED - AT CAPACITY": return "Closed — at capacity"
        case "CLOSED - CLEARED FOR TURTLES": return "Closed — turtles"
        case "CLOSING IN PROGRESS": return "Closing now"
        case "OPEN - ENTRANCE ONLY": return "Entrance only"
        case "4X4 ONLY": return "4x4 only"
        default:
            let phrase = card.ramp.accessStatus.lowercased().replacingOccurrences(of: " - ", with: " — ")
            return phrase.prefix(1).uppercased() + phrase.dropFirst()
        }
    }

    /// The forward-looking line: the server's outlook string when there is
    /// one, the since line otherwise, "as of" when stale.
    private var thirdLine: String {
        if let staleAsOf {
            return "as of \(staleAsOf)"
        }
        if let short = card.shortLine, !short.isEmpty {
            return short
        }
        guard let since = card.ramp.statusSince else { return " " }
        return "since \(SinceFormatter.string(from: since))"
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        RampGridView(
            cards: [
                TVRampCardModel(ramp: PreviewFixtures.mixedRamps[0], state: .limited,
                                shortLine: nil),
                TVRampCardModel(ramp: PreviewFixtures.mixedRamps[1], state: .closed,
                                shortLine: "often back open by 5:30pm"),
                TVRampCardModel(ramp: PreviewFixtures.mixedRamps[2], state: .open,
                                shortLine: "could close on the ~3pm tide"),
                TVRampCardModel(ramp: PreviewFixtures.mixedRamps[3], state: .open,
                                shortLine: "tide closure possible soon"),
                TVRampCardModel(ramp: PreviewFixtures.mixedRamps[4], state: .open,
                                shortLine: nil),
            ],
            staleAsOf: nil
        )
        .padding(.horizontal, 64)
    }
}

#Preview("Overnight") {
    ZStack {
        Color(boardHex: 0x0A1228).ignoresSafeArea()
        RampGridView(
            cards: PreviewFixtures.openRamps.map {
                TVRampCardModel(ramp: $0, state: .overnight, shortLine: "opens around 8am")
            },
            staleAsOf: nil
        )
        .padding(.horizontal, 64)
    }
}
#endif

import SwiftUI
import BeachStatus

/// One ramp on the board. Status is carried by the field itself: open is a
/// bordered card, limited and closed are solid fields. Radius 0 everywhere.
struct RampRowView: View {
    let ramp: Ramp
    var stale: Bool = false
    /// Server prediction hint ("closure likely ~1:30pm"); replaces the since
    /// line when set, italic so it reads as a forecast.
    var outlookHint: String? = nil
    /// The beach is shut overnight per the outlook: the row reads Closed
    /// whatever the county feed says, so it never contradicts "opens around
    /// 8am" sitting under it.
    var overnight: Bool = false
    @Environment(\.ground) private var ground

    private var category: StatusCategory {
        overnight ? .closed : ramp.category
    }

    private var field: StatusField {
        StatusField.field(for: category, isDay: ground.isDay)
    }

    private var statusWord: String {
        switch category {
        case .open: "Open"
        case .limited: "Limited"
        case .closed: "Closed"
        }
    }

    private var sinceLine: String {
        let clock = ramp.statusSince.map { SinceFormatter.string(from: $0) }
        if stale {
            return clock.map { "as of \($0)" } ?? "as of last contact"
        }
        return clock.map { "\(statusWord) since \($0)" } ?? statusWord
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ramp.rampDisplayName)
                    .font(.archivo(22, weight: .extraBold))
                    .tracking(22 * ArchivoTracking.rampName)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                if let outlookHint, !stale {
                    Text(outlookHint)
                        .font(.archivo(11))
                        .italic()
                        .opacity(0.75)
                } else {
                    Text(sinceLine)
                        .font(.archivo(11))
                        .opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Rectangle()
                    .fill(field.mark)
                    .frame(width: 10, height: 20)
                Text(statusWord)
                    .font(.archivo(15, weight: .extraBold))
            }
            .padding(.leading, 12)
        }
        .foregroundStyle(field.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .background(field.fill)
        .overlay(Rectangle().strokeBorder(field.border, lineWidth: 2))
        .opacity(stale ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(ramp.rampDisplayName), \(statusWord.lowercased())"
        if let since = ramp.statusSince {
            text += " since \(SinceFormatter.string(from: since))"
        }
        if let outlookHint, !stale { text += ", \(outlookHint)" }
        if stale { text += ", data stale" }
        return text
    }
}

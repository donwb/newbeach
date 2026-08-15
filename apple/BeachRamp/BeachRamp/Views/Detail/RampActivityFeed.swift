import SwiftUI
import BeachStatus

/// The activity feed scoped to one ramp: last 48 hours, tabular time column.
struct RampActivityFeed: View {
    let rampName: String
    let entries: [ActivityEntry]
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("This ramp · last 48 hours".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)

            if entries.isEmpty {
                Text("No changes in the last 48 hours.")
                    .font(.archivo(12))
                    .foregroundStyle(t.ink2)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(timeLabel(entry.recordedAt))
                                .font(.archivo(13))
                                .monospacedDigit()
                                .foregroundStyle(t.ink2)
                                .frame(width: 104, alignment: .leading)
                            Text(entry.statusDisplay)
                                .font(.archivo(13, weight: .bold))
                                .foregroundStyle(t.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) {
                            if entry.id != entries.last?.id {
                                Rectangle().fill(t.rule2).frame(height: 1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// "Today 3:48 PM" / "Yest 8:14 PM" / "Jun 8".
    private func timeLabel(_ date: Date) -> String {
        let base = SinceFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) {
            return "Today \(base)"
        }
        return base
    }
}

/// The other ramps in this city, two columns with heavy top rules; the
/// current ramp reads in accent. Taps swap the detail in place so you can
/// flip between ramps without going back.
struct OtherRampsGrid: View {
    let ramps: [Ramp]
    let currentID: String
    let select: (Ramp) -> Void
    @Environment(\.ground) private var ground

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]
    }

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Other ramps".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(ramps) { ramp in
                    let isCurrent = ramp.accessID == currentID
                    Button {
                        if !isCurrent { select(ramp) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle()
                                .fill(isCurrent ? t.accent : t.ink.opacity(0.8))
                                .frame(height: 4)
                            Text(ramp.rampDisplayName)
                                .font(.archivo(17, weight: .extraBold))
                                .foregroundStyle(isCurrent ? t.accent : t.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressTintButtonStyle())
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
    }
}

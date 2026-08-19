import SwiftUI
import BeachStatus

/// What the surf panel renders. Every string is server-built; `hasRead`
/// false is the stale-buoy state ("No surf read right now").
struct SurfPanelModel {
    let line: String
    /// "Rip risk low" plain, elevated risks bold amber. Nil hides the slot.
    let ripLabel: String?
    let ripElevated: Bool
    /// "Knee-high · 6s · buoy read 40 min ago"
    let detail: String
    let hasRead: Bool
}

/// One weekend day panel's display inputs.
struct DayPanelModel: Identifiable {
    let id: String
    /// "Saturday", or "Today · Saturday" when the slot's day is today —
    /// positions never move; only the label and copy change.
    let label: String
    let verdict: String
    let headline: String
    /// "93° · rain 20% · SW 8"
    let metrics: String
    /// "All 7 days ›" on the last panel.
    let cta: String?
}

/// The Ahead band of design v3: surf (1.3fr) plus the two weekend day
/// panels. The day panels are focusable and open the beach forecast
/// overlay; surf is ambient. When the weekend outlook is off, surf takes
/// the full row.
struct AheadBand: View {
    let surf: SurfPanelModel
    let days: [DayPanelModel]
    @FocusState.Binding var focusedDay: String?
    let onOpenForecast: () -> Void

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 18
            let unit = (geo.size.width - gap * CGFloat(days.count)) / (1.3 + CGFloat(days.count))
            HStack(alignment: .top, spacing: gap) {
                SurfPanel(model: surf)
                    .frame(width: days.isEmpty ? geo.size.width : unit * 1.3)
                ForEach(days) { day in
                    Button {
                        onOpenForecast()
                    } label: {
                        DayPanel(model: day)
                    }
                    .buttonStyle(DayPanelButtonStyle(isFocused: focusedDay == day.id))
                    .focused($focusedDay, equals: day.id)
                    .frame(width: unit)
                }
            }
        }
        .frame(height: 200)
        .focusSection()
    }
}

/// The surf read — an adjective, not a feature: one casual line, the rip
/// risk, and the buoy facts. Never a dedicated surf surface.
private struct SurfPanel: View {
    let model: SurfPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Surf")
                    .kickerStyle(opacity: 0.68)
                Spacer()
                if let rip = model.ripLabel {
                    Text(rip)
                        .font(.system(size: 22, weight: model.ripElevated ? .bold : .regular))
                        .foregroundStyle(model.ripElevated
                            ? BoardColor.amberAccent
                            : .white.opacity(model.hasRead ? 0.68 : 0.55))
                }
            }
            Text(model.line)
                .font(.system(size: 48, weight: .heavy))
                .tracking(48 * -0.02)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white.opacity(model.hasRead ? 1.0 : 0.72))
            Text(model.detail)
                .font(.system(size: 24))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(model.hasRead ? 0.75 : 0.6))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BoardColor.aheadField)
        .overlay(Rectangle().strokeBorder(.white.opacity(0.28), lineWidth: 2))
    }
}

/// One weekend day: label + verdict mark/word, the server's headline
/// verbatim, and the weather metrics.
private struct DayPanel: View {
    let model: DayPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(model.label)
                    .kickerStyle(opacity: 0.68)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(verdictMark)
                        .frame(width: 13, height: 22)
                    Text(verdictWord)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            Text(model.headline)
                .font(.system(size: 30, weight: .bold))
                .tracking(30 * -0.01)
                .lineSpacing(30 * 0.12)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Text(model.metrics)
                    .font(.system(size: 24))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if let cta = model.cta {
                    Text(cta)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(BoardColor.amberAccent)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var verdictMark: Color {
        BoardColor.verdictMark(for: model.verdict)
    }

    private var verdictWord: String {
        let display = model.verdict.replacingOccurrences(of: "_", with: " ")
        return display.prefix(1).uppercased() + display.dropFirst()
    }
}

/// Flat focus treatment for the day panels: the field and border brighten,
/// nothing scales or frosts.
private struct DayPanelButtonStyle: ButtonStyle {
    var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? Color.white.opacity(0.14) : BoardColor.dayPanelField)
            .overlay(Rectangle().strokeBorder(
                .white.opacity(isFocused ? 1.0 : 0.28), lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    @Previewable @FocusState var focusedDay: String?
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        AheadBand(
            surf: SurfPanelModel(
                line: "Pretty much flat out there",
                ripLabel: "Rip risk low",
                ripElevated: false,
                detail: "Knee-high · 6s · buoy read 40 min ago",
                hasRead: true
            ),
            days: [
                DayPanelModel(id: "2026-08-22", label: "Saturday", verdict: "good",
                              headline: "Best around 9 AM to 1 PM, clear of the tide",
                              metrics: "93° · rain 20% · SW 8", cta: nil),
                DayPanelModel(id: "2026-08-23", label: "Sunday", verdict: "great",
                              headline: "Wide open — any time works",
                              metrics: "91° · rain 10%", cta: "All 7 days ›"),
            ],
            focusedDay: $focusedDay,
            onOpenForecast: {}
        )
        .padding(.horizontal, 64)
    }
}
#endif

import SwiftUI

/// The ramp section heading of design v3 — the city selector lives here,
/// against the surface it drives: "RAMPS" label, the city at 38/heavy with
/// "‹ ›", a 2pt rule beneath; the right end carries the ramp count and the
/// Recent-changes affordance. Select on the city cycles to the next one.
struct RampHeading: View {
    let city: String
    /// "5 ramps · all open" / "3 open · 1 limited · 1 closed".
    let summary: String
    @FocusState.Binding var cityFocused: Bool
    @FocusState.Binding var recentChangesFocused: Bool
    let onNextCity: () -> Void
    let onRecentChanges: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 32) {
            Button {
                onNextCity()
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    Text("Ramps")
                        .kickerStyle(opacity: 0.68)
                    Text(city)
                        .font(.system(size: 38, weight: .heavy))
                        .tracking(38 * -0.02)
                        .foregroundStyle(.white)
                    Text("‹ ›")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .buttonStyle(FlatFocusButtonStyle(
                isFocused: cityFocused,
                horizontalPadding: 14,
                verticalPadding: 6,
                idleFill: 0,
                idleBorder: 0
            ))
            .focused($cityFocused)
            // Pull the chip back so its padding doesn't shift the left edge.
            .padding(.leading, -14)

            Spacer(minLength: 0)

            HStack(spacing: 26) {
                Text(summary)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.75))
                Button {
                    onRecentChanges()
                } label: {
                    Label("Recent changes", systemImage: "line.3.horizontal")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(recentChangesFocused ? 1.0 : 0.6))
                }
                .buttonStyle(FlatFocusButtonStyle(
                    isFocused: recentChangesFocused,
                    horizontalPadding: 14,
                    verticalPadding: 6,
                    idleFill: 0,
                    idleBorder: 0
                ))
                .focused($recentChangesFocused)
            }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.42)).frame(height: 2)
        }
        .focusSection()
    }
}

#if DEBUG
#Preview {
    @Previewable @FocusState var cityFocused: Bool
    @Previewable @FocusState var recentFocused: Bool
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        RampHeading(
            city: "New Smyrna Beach",
            summary: "5 ramps · all open",
            cityFocused: $cityFocused,
            recentChangesFocused: $recentFocused,
            onNextCity: {},
            onRecentChanges: {}
        )
        .padding(.horizontal, 64)
    }
}
#endif

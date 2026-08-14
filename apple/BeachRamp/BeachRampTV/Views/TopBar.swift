import SwiftUI

/// Lean header: the city selector on the left, the clock on the right. The
/// day's sun rhythm and the ramp tallies live in the timeline bar and the
/// color-coded tiles, so the header stays out of the way.
struct TopBar: View {
    let city: String
    let time: String
    let onNextCity: () -> Void

    @FocusState private var cityFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                onNextCity()
            } label: {
                HStack(spacing: 8) {
                    Text(city)
                        .font(.system(size: 40, weight: .bold))
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.title3)
                        .opacity(0.6)
                }
            }
            .buttonStyle(FlatFocusButtonStyle(
                isFocused: cityFocused,
                cornerRadius: 12,
                horizontalPadding: 16,
                verticalPadding: 8
            ))
            .focused($cityFocused)
            // Pull the chip back so its padding doesn't shift the title's left edge.
            .padding(.leading, -16)

            Spacer()

            Text(time)
                .font(.system(size: 38, weight: .light, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            TopBar(city: "New Smyrna Beach", time: "1:30 PM", onNextCity: {})
                .padding(60)
            Spacer()
        }
    }
}

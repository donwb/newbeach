import SwiftUI
import BeachStatus

/// The 110pt top band: brand, the weather display, the Beach outlook button,
/// and the clock. Never moves, never rescales — whatever is happening below,
/// this row holds still. The weather trio is a read-only display, not a
/// control; the outlook button is the only bordered element on the resting
/// screen, which is what makes it read as pressable among all the ruled type.
struct HeaderBand: View {
    let weatherCells: [WeatherCell]
    let time: String
    /// Minutes since the ramps feed last loaded, once stale. Nil = live.
    /// Not in the design mock — retained deliberately: freshness is
    /// safety-critical for this app.
    let staleMinutes: Int?
    /// The outlook button dims out of the focus graph while a surface is up.
    let surfaceOpen: Bool
    let focus: FocusState<RootFocus?>.Binding
    let onOpenOutlook: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            Text("Volusia Beach Info")
                .tv(32, .extraBold, tracking: -0.02)
                .foregroundStyle(TVInk.type)

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 34) {
                    ForEach(weatherCells) { cell in
                        cellText(cell)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                if let staleMinutes {
                    Text("Stale · \(staleMinutes) min")
                        .tv(24, .semiBold)
                        .foregroundStyle(TVInk.typeDim)
                        .accessibilityIdentifier("staleChip")
                }

                outlookButton

                Text(time)
                    .tv(44, .semiBold, tracking: -0.025)
                    .monospacedDigit()
                    .foregroundStyle(TVInk.type)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(TVInk.rule).frame(width: 2)
                    }
            }
        }
        .padding(.horizontal, TVMetrics.sidePad)
        .frame(height: TVMetrics.header)
        .focusSection()
    }

    /// Label + value as one Text run so the baseline math stays free. A
    /// symbol cell (sunrise/sunset) draws its glyph where the word would go.
    private func cellText(_ cell: WeatherCell) -> Text {
        let value = Text(cell.value).tv(28, .extraBold)
            .foregroundStyle(TVInk.type)
        if let symbol = cell.symbol {
            return Text(Image(systemName: symbol)).tv(24)
                .foregroundStyle(TVInk.typeMuted)
                + Text(" ") + value
        }
        return Text("\(cell.label) ").tv(28)
            .foregroundStyle(TVInk.typeMuted)
            + value
    }

    private var isFocused: Bool { focus.wrappedValue == .outlookButton }

    private var outlookButton: some View {
        Button(action: onOpenOutlook) {
            HStack(spacing: 16) {
                Text("Beach outlook")
                    .tv(28, .bold)
                    .foregroundStyle(isFocused ? TVInk.onSand : TVInk.type)
                Text("›")
                    .tv(28, .bold)
                    .foregroundStyle(isFocused ? TVInk.onSand : TVInk.sand)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Rectangle().fill(isFocused ? TVInk.sand : .clear))
            .overlay(Rectangle().strokeBorder(TVInk.sand, lineWidth: 2))
        }
        .buttonStyle(BareButtonStyle())
        // Disabled (not .focusable(false)) while a surface is open — a
        // .focusable modifier on a Button intercepts Select on tvOS.
        .disabled(surfaceOpen)
        .focused(focus, equals: .outlookButton)
        .accessibilityIdentifier("outlookButton")
    }
}

#if DEBUG
#Preview("Header", traits: .fixedLayout(width: 1920, height: 110)) {
    @Previewable @FocusState var focus: RootFocus?
    HeaderBand(
        weatherCells: [
            WeatherCell(label: "Sunrise", value: "6:59", symbol: "sunrise.fill"),
            WeatherCell(label: "Sunset", value: "7:52", symbol: "sunset.fill"),
            WeatherCell(label: "Water", value: "82°"),
            WeatherCell(label: "Air", value: "91°"),
            WeatherCell(label: "Wind", value: "SW 5"),
        ],
        time: "1:23 PM",
        staleMinutes: nil,
        surfaceOpen: false,
        focus: $focus,
        onOpenOutlook: {}
    )
    .background(TVSky.previewNoon)
}

#Preview("Header · stale", traits: .fixedLayout(width: 1920, height: 110)) {
    @Previewable @FocusState var focus: RootFocus?
    HeaderBand(
        weatherCells: [
            WeatherCell(label: "Sunrise", value: "6:59", symbol: "sunrise.fill"),
            WeatherCell(label: "Sunset", value: "7:52", symbol: "sunset.fill"),
            WeatherCell(label: "Water", value: "82°"),
            WeatherCell(label: "Air", value: "91°"),
            WeatherCell(label: "Wind", value: "SW 5"),
        ],
        time: "1:23 PM",
        staleMinutes: 14,
        surfaceOpen: false,
        focus: $focus,
        onOpenOutlook: {}
    )
    .background(TVSky.previewNight)
}
#endif

import SwiftUI
import BeachStatus

/// The board's hero: brand row, city control, and the verdict, all on the raw
/// sky. Height is content-driven — no spacer pushing the verdict down.
struct SkyHeroView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.ground) private var ground

    private static let clockFormat = Date.FormatStyle(date: .omitted, time: .shortened)
        .locale(Locale(identifier: "en_US"))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow
            cityControl
                .padding(.top, 16)
            VerdictView(verdict: viewModel.verdict())
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(alignment: .top) {
            ground.heroScrim.ignoresSafeArea(edges: .top)
        }
    }

    private var brandRow: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(viewModel.isStale
                          ? Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255)
                          : Color(red: 0x2A / 255, green: 0xE0 / 255, blue: 0x7A / 255))
                    .frame(width: 9, height: 9)
                Text("Beach Ramp Status")
                    .font(.archivo(16, weight: .extraBold))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ground.palette.phaseName.uppercased())
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .foregroundStyle(.white.opacity(0.72))
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: Self.clockFormat)
                        .font(.archivo(15))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var cityControl: some View {
        Menu {
            ForEach(viewModel.cities, id: \.self) { city in
                Button(city) { viewModel.selectedCity = city }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedCity ?? "All Cities")
                    .font(.archivo(15, weight: .extraBold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("City: \(viewModel.selectedCity ?? "All Cities")")
    }
}

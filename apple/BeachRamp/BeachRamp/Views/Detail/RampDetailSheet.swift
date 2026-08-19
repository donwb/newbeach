import SwiftUI
import BeachStatus

/// The iPad ramp detail: a 760×762 panel over the dimmed board — a sheet in
/// spirit, drawn by hand so the 2px ink border and zero radius survive.
/// The board stays visible behind it because comparing this ramp against the
/// others is the point.
struct RampDetailSheet: View {
    @Bindable var viewModel: BeachViewModel
    @State var ramp: Ramp
    let dismiss: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        ZStack {
            Color(red: 6 / 255, green: 20 / 255, blue: 32 / 255).opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .frame(width: 760, height: 762)
                .background {
                    ZStack {
                        ground.skyGradient
                        ground.veil
                        // At night the veil vanishes; keep the panel legible
                        // over the dim with a deep ground.
                        if !ground.isDay {
                            Color(red: 4 / 255, green: 24 / 255, blue: 34 / 255).opacity(0.85)
                        }
                    }
                }
                .overlay(Rectangle().strokeBorder(ground.tokens.rule, lineWidth: 2))
        }
        .task(id: ramp.accessID) {
            await viewModel.loadDetail(for: ramp)
        }
    }

    private var panel: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kicker.uppercased())
                                .font(.archivo(11, weight: .bold))
                                .tracking(11 * ArchivoTracking.kicker)
                                .foregroundStyle(t.ink2)
                            Text(ramp.rampDisplayName)
                                .font(.archivo(46, weight: .extraBold))
                                .tracking(46 * ArchivoTracking.rampName)
                                .foregroundStyle(t.ink)
                        }
                        Spacer()
                        Button {
                            viewModel.toggleFavorite(ramp)
                        } label: {
                            Image(systemName: viewModel.isFavorite(ramp) ? "star.fill" : "star")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(viewModel.isFavorite(ramp) ? t.accent : t.ink2)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(action: dismiss) {
                            Text("Done")
                                .font(.archivo(16, weight: .extraBold))
                                .foregroundStyle(t.accent)
                                .frame(height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressTintButtonStyle())
                    }
                    .padding(.bottom, 16)

                    DetailStatusBand(
                        ramp: ramp,
                        projection: viewModel.projection(for: ramp),
                        outlookLine: viewModel.outlookLine(for: ramp),
                        surfLine: viewModel.outlook?.surfReport?.line,
                        statusSize: 28
                    )

                    TodayStatusBandView(intervals: viewModel.intervalsByRamp[ramp.accessID])
                        .padding(.top, 22)

                    FactsGrid(ramp: ramp, nearestCam: viewModel.selectedCamera?.name, columns: 4)
                        .padding(.top, 22)

                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            thresholdChart
                        }
                        .frame(maxWidth: .infinity)
                        RampActivityFeed(
                            rampName: ramp.rampDisplayName,
                            entries: viewModel.activityByRamp[ramp.accessID] ?? []
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                }
                .padding(28)
            }

            // Other ramps, pinned as the panel's footer.
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(t.rule).frame(height: 2)
                HStack(spacing: 18) {
                    ForEach(viewModel.cityRamps) { other in
                        let isCurrent = other.accessID == ramp.accessID
                        Button {
                            if !isCurrent { ramp = other }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Rectangle()
                                    .fill(isCurrent ? t.accent : t.ink.opacity(0.8))
                                    .frame(height: 3)
                                Text(other.shortDisplayName)
                                    .font(.archivo(14, weight: .extraBold))
                                    .foregroundStyle(isCurrent ? t.accent : t.ink)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressTintButtonStyle())
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
                .padding(.top, 6)
            }
        }
    }

    private var kicker: String {
        if let order = ramp.sortOrder {
            return String(format: "Ramp %02d · %@", order, ramp.cityDisplay)
        }
        return ramp.cityDisplay
    }

    @ViewBuilder
    private var thresholdChart: some View {
        let t = ground.tokens
        Text("Tide against this ramp".uppercased())
            .font(.archivo(10, weight: .bold))
            .tracking(10 * ArchivoTracking.kicker)
            .foregroundStyle(t.ink2)
        if let chart = viewModel.tideChart {
            let window = Date().addingTimeInterval(-6 * 3600)...Date().addingTimeInterval(18 * 3600)
            let points = TideCurve.points(extremes: chart.highLow, in: window)
            if points.count >= 2 {
                TideCurveShapeView(points: points, range: window, height: 120,
                                   threshold: ramp.closureHeightFt)
            }
        }
        if let feet = ramp.closureHeightFt {
            Text(String(format: "Dashed line — %.1f ft, the height this ramp closes above.", feet))
                .font(.archivo(12))
                .foregroundStyle(t.ink2)
        }
    }
}

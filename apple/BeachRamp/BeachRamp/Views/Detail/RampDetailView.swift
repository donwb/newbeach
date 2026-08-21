import SwiftUI
import BeachStatus

/// One ramp, in full: status band with the forward-looking line, today's
/// status band, facts, the tide against this ramp's threshold, its 48-hour
/// feed, and the other ramps. Pushed on iPhone; sits on the veiled ground —
/// the sky hero is the board's signature, not repeated here.
struct RampDetailView: View {
    @Bindable var viewModel: BeachViewModel
    @State var ramp: Ramp
    @Environment(\.ground) private var ground
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = ground.tokens
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 18)

                Rectangle().fill(t.rule).frame(height: 2)

                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                DetailStatusBand(ramp: ramp, projection: viewModel.projection(for: ramp),
                                 outlookLine: viewModel.outlookLine(for: ramp),
                                 surfLine: viewModel.outlook?.surfReport?.line)

                TodayStatusBandView(intervals: viewModel.intervalsByRamp[ramp.accessID])
                    .padding(.horizontal, 18)
                    .padding(.top, 22)

                FactsGrid(ramp: ramp, nearestCam: viewModel.selectedCamera?.name, scheduleHours: viewModel.scheduleHours)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)

                Rectangle().fill(t.rule).frame(height: 2)
                    .padding(.top, 22)

                threshold
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                Rectangle().fill(t.rule).frame(height: 2)
                    .padding(.top, 14)

                RampActivityFeed(
                    rampName: ramp.rampDisplayName,
                    entries: viewModel.activityByRamp[ramp.accessID] ?? []
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Rectangle().fill(t.rule).frame(height: 2)
                    .padding(.top, 14)

                OtherRampsGrid(
                    ramps: viewModel.cityRamps,
                    currentID: ramp.accessID
                ) { other in
                    ramp = other
                    Task { await viewModel.loadDetail(for: other) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background {
            ZStack {
                ground.skyGradient
                ground.veil
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: ramp.accessID) {
            await viewModel.loadDetail(for: ramp)
        }
    }

    private var topBar: some View {
        let t = ground.tokens
        return HStack {
            Button {
                dismiss()
            } label: {
                Text("← All \(shortCity) ramps")
                    .font(.archivo(15, weight: .bold))
                    .foregroundStyle(t.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressTintButtonStyle())
            Spacer()
            Button {
                viewModel.toggleFavorite(ramp)
            } label: {
                Image(systemName: viewModel.isFavorite(ramp) ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(viewModel.isFavorite(ramp) ? t.accent : t.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressTintButtonStyle())
            .accessibilityLabel(viewModel.isFavorite(ramp) ? "Remove favorite" : "Add favorite")
        }
    }

    /// "New Smyrna Beach" → "New Smyrna" for the back link, mirroring the mock.
    private var shortCity: String {
        ramp.cityDisplay.replacingOccurrences(of: " Beach", with: "")
    }

    private var header: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            Text(ramp.rampDisplayName)
                .font(.archivo(34, weight: .extraBold))
                .tracking(34 * ArchivoTracking.rampName)
                .foregroundStyle(t.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kicker: String {
        if let order = ramp.sortOrder {
            return String(format: "Ramp %02d · %@", order, ramp.cityDisplay)
        }
        return ramp.cityDisplay
    }

    @ViewBuilder
    private var threshold: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Tide against this ramp".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)

            if let chart = viewModel.tideChart {
                let window = thresholdWindow
                let points = TideCurve.points(extremes: chart.highLow, in: window)
                if points.count >= 2 {
                    TideCurveShapeView(
                        points: points,
                        range: window,
                        height: 120,
                        threshold: ramp.closureHeightFt
                    )
                } else {
                    Text("Tide data unavailable")
                        .font(.archivo(13))
                        .foregroundStyle(t.ink2)
                }
            }

            if let feet = ramp.closureHeightFt {
                Text(String(format: "Dashed line — %.1f ft, the height this ramp closes above.", feet))
                    .font(.archivo(12))
                    .foregroundStyle(t.ink2)
            }
        }
    }

    private var thresholdWindow: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-6 * 3600)...now.addingTimeInterval(18 * 3600)
    }
}

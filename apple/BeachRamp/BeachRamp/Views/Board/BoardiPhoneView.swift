import SwiftUI
import BeachStatus

/// The iPhone board: one scroll, verdict first. The hero sits on the raw sky;
/// everything below the sheet rule sits on the veil — which at night stops
/// existing, leaving the sky to continue through the whole page.
struct BoardiPhoneView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.ground) private var ground

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SkyHeroView(viewModel: viewModel)
                sheet
            }
        }
        .background {
            ground.skyGradient.ignoresSafeArea()
        }
    }

    /// Everything below the hero. The veil is the sheet's ground; it extends
    /// well past the content so overscroll never exposes raw sky at day.
    private var sheet: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 0) {
            StatStripView(
                tideInfo: viewModel.tideInfo,
                tideChart: viewModel.tideChart,
                weather: viewModel.weather
            )

            FilterBarView(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.top, 12)

            rampList
                .padding(.horizontal, 18)
                .padding(.top, 12)

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 22)

            TideSectionView(tideInfo: viewModel.tideInfo, tideChart: viewModel.tideChart)
                .padding(.horizontal, 18)
                .padding(.top, 12)

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 14)

            ForecastRow(weather: viewModel.weather)
                .padding(.horizontal, 18)
                .padding(.top, 12)

            if viewModel.surfReportLine != nil {
                Rectangle().fill(t.rule2).frame(height: 1)
                    .padding(.top, 14)
                SurfReportView(line: viewModel.surfReportLine, detail: viewModel.surfReportDetail())
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
            }

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 14)

            if viewModel.weekend != nil {
                WeekendSectionView(weekend: viewModel.weekend)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                Rectangle().fill(t.rule).frame(height: 2)
                    .padding(.top, 14)
            }

            if let camera = viewModel.selectedCamera {
                CamRowView(cameraName: camera.name) {
                    viewModel.camPresented = true
                }
                .padding(.horizontal, 18)

                Rectangle().fill(t.rule2).frame(height: 1)
            }

            RecentChangesList(entries: viewModel.recentActivity)
                .padding(.horizontal, 18)
                .padding(.top, 12)

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 14)

            BoardFooterView(updatedAt: viewModel.lastSuccessfulRefresh)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 26)
        }
        .background {
            ground.veil.padding(.bottom, -1200)
        }
    }

    @ViewBuilder
    private var rampList: some View {
        let t = ground.tokens
        if viewModel.isLoading && viewModel.ramps.isEmpty {
            ProgressView("Loading ramps…")
                .font(.archivo(13))
                .tint(t.ink2)
                .foregroundStyle(t.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if viewModel.filteredRamps.isEmpty {
            Text("No ramps match this filter.")
                .font(.archivo(13))
                .foregroundStyle(t.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(spacing: 10) {
                ForEach(viewModel.filteredRamps) { ramp in
                    NavigationLink(value: ramp) {
                        RampRowView(ramp: ramp, stale: viewModel.isStale,
                                    outlookHint: viewModel.outlookHint(for: ramp),
                                    overnight: viewModel.isOvernightClosed(ramp))
                    }
                    .buttonStyle(PressTintButtonStyle())
                }
            }
        }
    }
}

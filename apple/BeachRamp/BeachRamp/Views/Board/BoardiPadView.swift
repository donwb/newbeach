import SwiftUI
import BeachStatus

/// The iPad board: one wide page, not a split view — there is no hierarchy
/// here. Landscape keeps a 372pt conditions rail; portrait dissolves it into
/// the flow. Ramp detail presents as a centered panel over the dimmed board.
struct BoardiPadView: View {
    @Bindable var viewModel: BeachViewModel
    @Environment(\.ground) private var ground
    @State private var detailRamp: Ramp?

    var body: some View {
        GeometryReader { geo in
            // QA hook: --force-wide renders the landscape arrangement in any
            // window (simulator panels can't rotate the device).
            let isLandscape = geo.size.width > geo.size.height
                || ProcessInfo.processInfo.arguments.contains("--force-wide")
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        skyBand(isLandscape: isLandscape)
                        if isLandscape {
                            landscapeBody
                        } else {
                            portraitBody
                        }
                    }
                }
                .background { ground.skyGradient.ignoresSafeArea() }

                if let ramp = detailRamp {
                    RampDetailSheet(viewModel: viewModel, ramp: ramp) {
                        detailRamp = nil
                    }
                }
            }
        }
    }

    private var pagePadding: CGFloat { 34 }

    // MARK: - Sky band

    private func skyBand(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(viewModel.isStale
                              ? Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255)
                              : Color(red: 0x2A / 255, green: 0xE0 / 255, blue: 0x7A / 255))
                        .frame(width: 10, height: 10)
                    Text("Beach Ramp Status")
                        .font(.archivo(20, weight: .extraBold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ground.palette.phaseName.uppercased())
                        .font(.archivo(11, weight: .bold))
                        .tracking(11 * ArchivoTracking.kicker)
                        .foregroundStyle(.white.opacity(0.72))
                    TimelineView(.everyMinute) { context in
                        Text(SinceFormatter.clock(context.date))
                            .font(.archivo(19))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            }

            cityTabs
                .padding(.top, 14)

            if isLandscape {
                // 1.55fr / 1fr: headline left, stat cells right.
                GeometryReader { geo in
                    let gap: CGFloat = 34
                    HStack(alignment: .top, spacing: gap) {
                        VerdictView(verdict: viewModel.verdict(), headlineSize: 52, sublineSize: 18)
                            .frame(width: (geo.size.width - gap) * 0.608, alignment: .leading)
                        skyStatCells
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 170)
                .padding(.top, 22)
            } else {
                VerdictView(verdict: viewModel.verdict(), headlineSize: 42, sublineSize: 18)
                    .padding(.top, 22)
                skyStatCells
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(alignment: .top) {
            ground.heroScrim.ignoresSafeArea(edges: .top)
        }
    }

    private var cityTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(viewModel.cities, id: \.self) { city in
                    let isActive = viewModel.selectedCity == city
                    Button {
                        viewModel.selectedCity = city
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(city.uppercased())
                                .font(.archivo(12, weight: .bold))
                                .tracking(12 * ArchivoTracking.kicker)
                                .foregroundStyle(.white.opacity(isActive ? 1 : 0.66))
                            Rectangle()
                                .fill(isActive
                                      ? Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x4D / 255)
                                      : .clear)
                                .frame(height: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
        }
    }

    /// The verdict row's three stat cells, on the sky: white type, 1px rules.
    private var skyStatCells: some View {
        HStack(alignment: .top, spacing: 0) {
            skyStat("Tide", value: tideValue, detail: viewModel.tideInfo.map { $0.isRising ? "Rising" : "Falling" })
            skyStat("Water · Air", value: tempsValue, detail: viewModel.weather?.current.description)
            skyStat("Wind", value: windValue, detail: viewModel.weather?.current.windDirection)
        }
    }

    private func skyStat(_ label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(.white.opacity(0.5)).frame(height: 1)
            Text(label.uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
            Text(value)
                .font(.archivo(26, weight: .extraBold))
                .monospacedDigit()
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.archivo(12))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 18)
        .accessibilityElement(children: .combine)
    }

    private var tideValue: String {
        guard let chart = viewModel.tideChart,
              let point = chart.hourly.min(by: {
                  abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow)
              }) else { return "—" }
        return String(format: "%.1f ft", point.height)
    }

    private var tempsValue: String {
        let water = viewModel.tideInfo?.waterTempAvg.map { "\(Int($0.rounded()))°" } ?? "—"
        let air = viewModel.weather?.current.temperatureF.map { "\(Int($0.rounded()))°" } ?? "—"
        return "\(water) · \(air)"
    }

    private var windValue: String {
        guard let speed = viewModel.weather?.current.windSpeed else { return "—" }
        return speed.replacingOccurrences(of: " mph", with: "") + " mph"
    }

    // MARK: - Landscape

    private var landscapeBody: some View {
        let t = ground.tokens
        return HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 0) {
                filterRow
                rampGrid(columns: 3, minHeight: 152)
                    .padding(.top, 14)
                Rectangle().fill(t.rule).frame(height: 2)
                    .padding(.top, 24)
                RecentChangesList(entries: viewModel.recentActivity)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            conditionsRail
                .frame(width: 372)
        }
        .padding(.horizontal, pagePadding)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .background { ground.veil.padding(.bottom, -1600) }
    }

    private var conditionsRail: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 0) {
            TideSectionView(tideInfo: viewModel.tideInfo, tideChart: viewModel.tideChart, height: 104)
            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 18)
            ForecastRow(weather: viewModel.weather)
                .padding(.top, 12)
            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 18)
            camRail
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var camRail: some View {
        let t = ground.tokens
        if viewModel.selectedCamera != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Live cam · \(viewModel.selectedCamera?.name ?? "")".uppercased())
                        .font(.archivo(10, weight: .bold))
                        .tracking(10 * ArchivoTracking.kicker)
                        .foregroundStyle(t.ink2)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.camPresented = true
                    } label: {
                        Text("Full screen ›")
                            .font(.archivo(12, weight: .extraBold))
                            .foregroundStyle(t.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressTintButtonStyle())
                }
                BeachCamView(
                    url: viewModel.videoStreamURL,
                    rebuildToken: viewModel.videoStreamGeneration,
                    onPlaybackFailure: { viewModel.refreshVideoStream() }
                )
            }
        }
    }

    // MARK: - Portrait

    private var portraitBody: some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 0) {
            filterRow
            rampGrid(columns: 2, minHeight: 116)
                .padding(.top, 14)

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 24)

            HStack(alignment: .top, spacing: 28) {
                TideSectionView(tideInfo: viewModel.tideInfo, tideChart: viewModel.tideChart, height: 104)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    ForecastRow(weather: viewModel.weather)
                    if let water = viewModel.tideInfo?.waterTempAvg {
                        Text("Water \(Int(water.rounded()))°")
                            .font(.archivo(15, weight: .extraBold))
                            .foregroundStyle(t.ink)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 12)

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 18)

            // The cam at full width, uncropped — height follows the pano's
            // own 1280/270 aspect (~160pt at portrait width).
            if viewModel.selectedCamera != nil {
                BeachCamView(
                    url: viewModel.videoStreamURL,
                    rebuildToken: viewModel.videoStreamGeneration,
                    onPlaybackFailure: { viewModel.refreshVideoStream() }
                )
                .padding(.top, 12)
                .onTapGesture { viewModel.camPresented = true }
            }

            Rectangle().fill(t.rule).frame(height: 2)
                .padding(.top, 18)

            RecentChangesList(entries: viewModel.recentActivity)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .background { ground.veil.padding(.bottom, -1600) }
    }

    // MARK: - Shared pieces

    private var filterRow: some View {
        let t = ground.tokens
        return HStack {
            FilterBarView(viewModel: viewModel)
            Spacer()
            Button {
                viewModel.favoritesOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .bold))
                    Text("Favorites")
                        .font(.archivo(14, weight: .extraBold))
                }
                .foregroundStyle(viewModel.favoritesOnly ? .white : t.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(viewModel.favoritesOnly ? t.accent : .clear)
                .overlay {
                    if !viewModel.favoritesOnly {
                        Rectangle().strokeBorder(t.rule, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressTintButtonStyle())
            .accessibilityAddTraits(viewModel.favoritesOnly ? .isSelected : [])
        }
    }

    private func rampGrid(columns: Int, minHeight: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns),
            spacing: 14
        ) {
            ForEach(viewModel.filteredRamps) { ramp in
                Button {
                    detailRamp = ramp
                } label: {
                    RampGridTile(
                        ramp: ramp,
                        stale: viewModel.isStale,
                        isFavorite: viewModel.isFavorite(ramp),
                        minHeight: minHeight,
                        outlookHint: viewModel.outlookHint(for: ramp),
                        toggleFavorite: { viewModel.toggleFavorite(ramp) }
                    )
                }
                .buttonStyle(PressTintButtonStyle())
            }
        }
    }
}

/// One ramp as a grid card: kicker + star, name, status mark + word + since.
struct RampGridTile: View {
    let ramp: Ramp
    let stale: Bool
    let isFavorite: Bool
    var minHeight: CGFloat = 152
    /// Server prediction hint; replaces the since line when set.
    var outlookHint: String? = nil
    let toggleFavorite: () -> Void
    @Environment(\.ground) private var ground

    private var field: StatusField {
        StatusField.field(for: ramp.category, isDay: ground.isDay)
    }

    private var statusWord: String {
        switch ramp.category {
        case .open: "Open"
        case .limited: "Limited"
        case .closed: "Closed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(ramp.sortOrder.map { String(format: "Ramp %02d", $0) } ?? " ")
                    .font(.archivo(10, weight: .bold))
                    .tracking(10 * ArchivoTracking.kicker)
                    .textCase(.uppercase)
                    .foregroundStyle(field.text2)
                Spacer()
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(field.text.opacity(isFavorite ? 1 : 0.55))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
            }
            Text(ramp.rampDisplayName)
                .font(.archivo(27, weight: .extraBold))
                .tracking(27 * ArchivoTracking.rampName)
                .foregroundStyle(field.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                Rectangle().fill(field.mark).frame(width: 10, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusWord)
                        .font(.archivo(15, weight: .extraBold))
                        .foregroundStyle(field.text)
                    if let outlookHint, !stale {
                        Text(outlookHint)
                            .font(.archivo(11))
                            .italic()
                            .foregroundStyle(field.text2)
                    } else if let since = ramp.statusSince {
                        Text(stale ? "as of \(SinceFormatter.string(from: since))"
                                   : "since \(SinceFormatter.string(from: since))")
                            .font(.archivo(11))
                            .foregroundStyle(field.text2)
                    }
                }
            }
        }
        .padding(14)
        .frame(minHeight: minHeight, alignment: .top)
        .background(field.fill)
        .overlay(Rectangle().strokeBorder(field.border, lineWidth: 2))
        .opacity(stale ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ramp.rampDisplayName), \(statusWord.lowercased())")
    }
}

/// Four-up forecast strip from the NWS daytime periods.
struct ForecastRow: View {
    let weather: WeatherInfo?
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Forecast".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            HStack(alignment: .top, spacing: 0) {
                ForEach(periods, id: \.name) { period in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortName(period.name).uppercased())
                            .font(.archivo(10, weight: .bold))
                            .tracking(10 * ArchivoTracking.kicker)
                            .foregroundStyle(t.ink2)
                        Text("\(period.temperature)°")
                            .font(.archivo(22, weight: .extraBold))
                            .monospacedDigit()
                            .foregroundStyle(t.ink)
                        Text(condensed(period.shortDescription))
                            .font(.archivo(11))
                            .foregroundStyle(t.ink2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var periods: [ForecastPeriod] {
        (weather?.forecast ?? []).filter(\.isDaytime).prefix(4).map { $0 }
    }

    private func shortName(_ name: String) -> String {
        if name.lowercased() == "today" || name.lowercased() == "this afternoon" { return "Today" }
        return String(name.prefix(3))
    }

    private func condensed(_ description: String) -> String {
        // "Slight Chance Showers And Thunderstorms" → "Storms"; otherwise the
        // first two words ("Mostly Sunny") carry the gist.
        let lower = description.lowercased()
        if lower.contains("thunderstorm") { return "Storms" }
        if lower.contains("shower") || lower.contains("rain") { return "Showers" }
        return description.split(separator: " ").prefix(2).joined(separator: " ")
    }
}

/// The city-wide activity feed under the ramp grid.
struct RecentChangesList: View {
    let entries: [ActivityEntry]
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent changes".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            if entries.isEmpty {
                Text("No changes yet today.")
                    .font(.archivo(12))
                    .foregroundStyle(t.ink2)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.prefix(6)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(SinceFormatter.string(from: entry.recordedAt))
                                .font(.archivo(13))
                                .monospacedDigit()
                                .foregroundStyle(t.ink2)
                                .frame(width: 104, alignment: .leading)
                            Text(entry.rampDisplayName ?? entry.accessID)
                                .font(.archivo(13, weight: .extraBold))
                                .foregroundStyle(t.ink)
                                .frame(width: 150, alignment: .leading)
                            Text(entry.statusDisplay)
                                .font(.archivo(13))
                                .foregroundStyle(t.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(t.rule2).frame(height: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

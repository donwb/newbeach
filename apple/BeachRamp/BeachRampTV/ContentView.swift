//
//  ContentView.swift
//  BeachRampTV
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import Charts
import BeachStatus

/// tvOS ambient dashboard — full-screen status board with ramps, tide, weather.
/// The background tracks the real sun for New Smyrna Beach, shifting through
/// dawn, day, golden hour, and a dimmed night as the day progresses.
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    @State private var sunriseText = ""
    @State private var sunsetText = ""
    @State private var solarDay: Date?
    @State private var timeTimer: Timer?

    private let solar = SolarCalculator.newSmyrnaBeach

    /// Eastern time — the beach's local zone, used for the clock and sun times.
    private static let easternZone = TimeZone(identifier: "America/New_York")!

    private var palette: SkyPalette { SkyPalette.forSun(altitude: sunAltitude, isRising: sunRising) }

    var body: some View {
        ZStack {
            palette.gradient
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading Beach Status…")
                    .font(.title2)
                    .foregroundStyle(.white)
            } else {
                dashboardContent
            }

            // Night dimming scrim — darkens the whole board after sunset.
            Color.black
                .opacity(palette.dimOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 2.0), value: sunAltitude)
        .task {
            await viewModel.loadAll()
            viewModel.startAutoRefresh()
            startClock()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: viewModel.previousCity()
            case .right: viewModel.nextCity()
            default: break
            }
        }
    }

    // MARK: - Dashboard Layout

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
                .padding(.horizontal, 60)
                .padding(.top, 40)

            // Info row: Ramps (2/3) | Tide+Weather combined (1/3)
            GeometryReader { geo in
                let railWidth = geo.size.width * 0.33
                HStack(alignment: .top, spacing: 24) {
                    rampGrid
                        .frame(maxWidth: .infinity)

                    tideWeatherCard
                        .frame(width: railWidth)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 16)

            Spacer()

            // Panoramic beach cam banner across the bottom
            TVVideoPlayerView(
                url: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                isPlaying: $viewModel.isVideoPlaying,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 8)

            // Bottom bar
            bottomBar
                .padding(.horizontal, 60)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            // Row 1: Title + Time + Sun times
            HStack(alignment: .firstTextBaseline) {
                Text("What's Up at the Beach")
                    .font(.largeTitle.weight(.bold))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(currentTime)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                    sunTimes
                }
            }

            // Row 2: City + Badges
            HStack {
                Text(viewModel.currentCity)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.caption)
                    Text("Cities")
                        .font(.caption)
                }
                .opacity(0.5)

                Spacer()

                HStack(spacing: 20) {
                    TVStatusBadge(count: viewModel.openCount, label: "Open", color: .tvStatusOpen)
                    TVStatusBadge(count: viewModel.limitedCount, label: "Limited", color: .tvStatusLimited)
                    TVStatusBadge(count: viewModel.closedCount, label: "Closed", color: .tvStatusClosed)
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// Sunrise / sunset pair shown beneath the clock.
    @ViewBuilder
    private var sunTimes: some View {
        if !sunriseText.isEmpty {
            HStack(spacing: 16) {
                Label(sunriseText, systemImage: "sunrise.fill")
                Label(sunsetText, systemImage: "sunset.fill")
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Ramp Grid

    private var rampGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(viewModel.displayedRamps) { ramp in
                    TVRampTile(ramp: ramp)
                }
            }
        }
    }

    // MARK: - Combined Tide + Weather Card

    private var tideWeatherCard: some View {
        HStack(alignment: .top, spacing: 20) {
            tideColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1)

            weatherColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassCard()
    }

    private var tideColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tide", systemImage: "water.waves")

            if let tide = viewModel.tideInfo {
                HStack(spacing: 6) {
                    Image(systemName: tide.isRising ? "arrow.up.right" : "arrow.down.right")
                    Text(tide.isRising ? "Rising" : "Falling")
                }
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            }

            // Mini tide chart
            if let data = viewModel.tideChart, !data.hourly.isEmpty {
                Chart {
                    ForEach(data.hourly) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(.white.opacity(0.1))
                    }
                    ForEach(data.hourly) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(.white.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 4))
                    }
                    RuleMark(x: .value("Now", data.currentTime))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 4))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 52)
            }

            // Water temp — large
            if let temp = viewModel.tideInfo?.waterTempAvg {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.water")
                    Text("Water \(Int(temp))°")
                }
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            }

            // One detail line: next high/low tide
            if let next = nextTide {
                Text("Next \(next.label) · \(next.timeDisplay)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var weatherColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Weather", systemImage: "cloud.sun.fill")

            if let current = viewModel.weather?.current {
                Text(current.tempDisplay)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)

                if let desc = current.description {
                    Text(desc)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Label(current.windDisplay, systemImage: "wind")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // One detail line: tomorrow's forecast
            if let tomorrow = tomorrowForecast {
                Text("\(tomorrow.shortName) \(tomorrow.tempDisplay)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    // MARK: - Derived Data

    /// The next upcoming high/low tide prediction.
    private var nextTide: TidePrediction? {
        guard let preds = viewModel.tideInfo?.predictions else { return nil }
        let now = Date()
        return preds.filter { $0.time > now }.min { $0.time < $1.time }
    }

    /// Tomorrow's daytime forecast (the second daytime period), for the one-line summary.
    private var tomorrowForecast: ForecastPeriod? {
        guard let forecast = viewModel.weather?.forecast else { return nil }
        let daytime = forecast.filter(\.isDaytime)
        return daytime.count > 1 ? daytime[1] : daytime.first
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                Text(error)
                    .font(.caption)
            }
            Spacer()
            Text("Auto-refreshes every 60s")
                .font(.caption)
                .opacity(0.4)
        }
        .foregroundStyle(.white.opacity(0.5))
    }

    // MARK: - Clock & Sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock, recomputes the sun's altitude (driving the background),
    /// and refreshes sunrise/sunset when the day rolls over.
    private func tick() {
        let now = Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = Self.easternZone
        currentTime = formatter.string(from: now)

        withAnimation(.easeInOut(duration: 2.0)) {
            sunAltitude = solar.altitude(at: now)
            sunRising = solar.isRising(at: now)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.easternZone
        if solarDay == nil || !calendar.isDate(solarDay!, inSameDayAs: now) {
            solarDay = now
            let events = solar.events(on: now, calendar: calendar)
            sunriseText = events.sunrise.map { formatter.string(from: $0) } ?? ""
            sunsetText = events.sunset.map { formatter.string(from: $0) } ?? ""
        }
    }
}

// MARK: - Glass Card Styling

/// Frosted-glass card surface — translucent material with a hairline highlight,
/// so cards read as floating over the sky rather than flat fills.
private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - TV Subviews

/// Status count badge for the TV header.
struct TVStatusBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Compact ramp tile for the TV grid — card with indicator + name on top, status below.
struct TVRampTile: View {
    let ramp: Ramp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: indicator + name
            HStack(spacing: 8) {
                Image(systemName: ramp.category.tvIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(ramp.category.tvColor)

                Text(ramp.rampName.titleCased)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            // Status text — full width
            Text(ramp.accessStatus.titleCased)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ramp.category.tvColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }
}

#Preview {
    ContentView()
}

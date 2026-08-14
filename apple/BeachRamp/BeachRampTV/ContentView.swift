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
    @FocusState private var focusedCamera: String?
    @State private var currentTime = ""
    @State private var sunAltitude: Double = 30
    @State private var sunRising = true
    /// The day's sun timeline (dawn → golden → noon → sunset → dusk), recomputed
    /// when the calendar day rolls over. Drives the bottom day-timeline bar.
    @State private var sunTimeline: SunTimeline?
    /// The current instant as a fraction (0…1) of the local day — the position of
    /// the "now" marker on the bar. Updated every tick.
    @State private var nowFraction: Double = 0
    @State private var solarDay: Date?
    @State private var timeTimer: Timer?

    private let solar = SolarCalculator.newSmyrnaBeach

    /// Eastern time — the beach's local zone, used for the clock and sun times.
    private static let easternZone = TimeZone(identifier: "America/New_York")!

    /// Gregorian calendar pinned to Eastern time, for day-boundary math.
    private static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternZone
        return cal
    }

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
        .onChange(of: focusedCamera) { _, id in
            // Channel-flip feel: moving focus across the strip switches the
            // active stream live. selectCamera is a no-op when the id is
            // unchanged or the camera's URL isn't resolved yet.
            if let id { viewModel.selectCamera(id) }
        }
    }

    // MARK: - Dashboard Layout

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // Top bar — lean: city selector + clock only
            TopBar(
                city: viewModel.currentCity,
                time: currentTime,
                onNextCity: { viewModel.nextCity() }
            )
            .padding(.horizontal, 60)
            .padding(.top, 28)

            // Info row: Ramps (2/3) | Tide+Weather combined (1/3). Sized to the
            // row's natural height (no greedy GeometryReader) so the taller
            // tide/weather card can't overflow onto the day-timeline bar below.
            HStack(alignment: .top, spacing: 24) {
                RampGridView(ramps: viewModel.displayedRamps)
                    .frame(maxWidth: .infinity)

                tideWeatherCard
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.33 }
            }
            .padding(.horizontal, 60)
            .padding(.top, 14)

            Spacer(minLength: 12)

            // Day-timeline bar — sun rhythm across the full width, above the cam
            DayTimelineBar(
                timeline: sunTimeline,
                nowFraction: nowFraction,
                errorMessage: viewModel.errorMessage
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 12)

            // Panoramic beach cam banner (the hero)
            TVVideoPlayerView(
                url: viewModel.videoStreamURL,
                rebuildToken: viewModel.videoStreamGeneration,
                isPlaying: $viewModel.isVideoPlaying,
                onPlaybackFailure: { viewModel.refreshVideoStream() }
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 6)

            // Coastline camera switcher across the bottom — pins placed
            // geographically along the coast
            if !viewModel.cameras.isEmpty {
                CoastlineRail(
                    cameras: viewModel.cameras,
                    selectedID: viewModel.selectedCameraID,
                    focusedCamera: $focusedCamera,
                    onSelect: { viewModel.selectCamera($0) }
                )
                .padding(.horizontal, 60)
                .padding(.bottom, 22)
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

    // MARK: - Clock & Sun

    private func startClock() {
        tick()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            tick()
        }
    }

    /// Updates the clock and the sun's altitude (driving the background), advances
    /// the timeline "now" marker, and rebuilds the day's sun timeline when the
    /// calendar day rolls over.
    private func tick() {
        let now = Date()
        let calendar = Self.easternCalendar

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = Self.easternZone
        currentTime = formatter.string(from: now)

        withAnimation(.easeInOut(duration: 2.0)) {
            sunAltitude = solar.altitude(at: now)
            sunRising = solar.isRising(at: now)
        }

        nowFraction = SunTimeline.dayFraction(of: now, calendar: calendar)

        if solarDay == nil || !calendar.isDate(solarDay!, inSameDayAs: now) {
            solarDay = now
            sunTimeline = SunTimeline(day: now, solar: solar, calendar: calendar, zone: Self.easternZone)
        }
    }
}

#Preview {
    ContentView()
}

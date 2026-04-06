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
struct ContentView: View {
    @State private var viewModel = TVViewModel()
    @State private var currentTime = ""
    @State private var timeTimer: Timer?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.tvOcean800, Color.tvOcean700, Color.tvOcean600],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading Beach Status…")
                    .font(.title2)
                    .foregroundStyle(.white)
            } else {
                dashboardContent
            }
        }
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

            // Main content: Ramps | Video | Tide+Weather
            HStack(alignment: .top, spacing: 24) {
                // Left: Ramp list
                rampList
                    .frame(width: 380)

                // Center: Video (sized to content)
                TVVideoPlayerView(
                    url: TVViewModel.videoStreamURL,
                    isPlaying: $viewModel.isVideoPlaying
                )

                // Right rail: Tide + Weather
                VStack(spacing: 16) {
                    tideRail
                    weatherRail
                }
                .frame(width: 240)
            }
            .padding(.horizontal, 60)
            .padding(.top, 16)

            Spacer()

            // Bottom bar
            bottomBar
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            // Row 1: Title + Time
            HStack(alignment: .firstTextBaseline) {
                Text("Beach Ramp Status")
                    .font(.largeTitle.weight(.bold))
                Spacer()
                Text(currentTime)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
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

    // MARK: - Ramp List (single column)

    private var rampList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(viewModel.displayedRamps) { ramp in
                    TVRampCard(ramp: ramp)
                }
            }
        }
    }

    // MARK: - Tide Rail

    private var tideRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "water.waves")
                    .font(.system(size: 16))
                Text("Tide")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(.white)

            if let tide = viewModel.tideInfo {
                HStack(spacing: 4) {
                    Image(systemName: tide.isRising ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 14))
                    Text("\(tide.tideDirection) \(tide.tidePercentage)%")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
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
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(x: .value("Now", data.currentTime))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 50)
            }

            // Predictions
            if let preds = viewModel.tideInfo?.predictions, !preds.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(preds) { pred in
                        HStack {
                            Text(pred.label)
                                .fontWeight(.bold)
                            Spacer()
                            Text(pred.timeDisplay)
                                .opacity(0.7)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(pred.type == "H" ? .white : .white.opacity(0.7))
                    }
                }
            }

            // Water temp
            if let temp = viewModel.tideInfo?.waterTempAvg {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.water")
                        .font(.system(size: 13))
                    Text("Water \(Int(temp))°F")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
        }
    }

    // MARK: - Weather Rail

    private var weatherRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 16))
                Text("Weather")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(.white)

            if let current = viewModel.weather?.current {
                Text(current.tempDisplay)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    if let desc = current.description {
                        Label(desc, systemImage: "cloud")
                    }
                    Label(current.windDisplay, systemImage: "wind")
                    if let gust = current.gustDisplay {
                        Label(gust, systemImage: "wind")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
            }

            // Forecast
            if let forecast = viewModel.weather?.forecast {
                let daytime = forecast.filter(\.isDaytime).prefix(3)
                VStack(spacing: 3) {
                    ForEach(Array(daytime)) { period in
                        HStack {
                            Text(period.shortName)
                                .opacity(0.7)
                            Spacer()
                            Text(period.tempDisplay)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
        }
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

    // MARK: - Clock

    private func startClock() {
        updateTime()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            updateTime()
        }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        currentTime = formatter.string(from: Date())
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

/// Individual ramp card for the TV grid.
struct TVRampCard: View {
    let ramp: Ramp

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ramp.category.tvIcon)
                .font(.system(size: 26))
                .foregroundStyle(ramp.category.tvColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(ramp.rampName.titleCased)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                Text(ramp.locationDisplay)
                    .font(.system(size: 17))
                    .opacity(0.7)
                    .lineLimit(1)
            }

            Spacer()

            Text(ramp.accessStatus.titleCased)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ramp.category.tvColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.08))
        }
    }
}

#Preview {
    ContentView()
}

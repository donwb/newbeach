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

            // Main content
            HStack(alignment: .top, spacing: 40) {
                // Left: Ramp grid
                rampGrid
                    .frame(maxWidth: .infinity)

                // Right: Tide + Weather
                VStack(spacing: 30) {
                    tideSection
                    weatherSection
                }
                .frame(width: 500)
            }
            .padding(.horizontal, 60)
            .padding(.top, 30)

            Spacer()

            // Bottom bar
            bottomBar
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Beach Ramp Status")
                    .font(.largeTitle.weight(.bold))
                Text("Volusia County, Florida")
                    .font(.title3)
                    .opacity(0.7)
            }

            Spacer()

            // Current time
            Text(currentTime)
                .font(.system(size: 48, weight: .light, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }

    // MARK: - Ramp Grid

    private var rampGrid: some View {
        VStack(alignment: .leading, spacing: 20) {
            // City header with counts
            HStack(spacing: 24) {
                Text(viewModel.currentCity)
                    .font(.title2.weight(.semibold))

                Spacer()

                HStack(spacing: 16) {
                    TVStatusBadge(count: viewModel.openCount, label: "Open", color: .tvStatusOpen)
                    TVStatusBadge(count: viewModel.limitedCount, label: "Limited", color: .tvStatusLimited)
                    TVStatusBadge(count: viewModel.closedCount, label: "Closed", color: .tvStatusClosed)
                }

                // City navigation hint
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.caption)
                    Text("Cities")
                        .font(.caption)
                }
                .opacity(0.5)
            }
            .foregroundStyle(.white)

            // Ramp cards grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(viewModel.displayedRamps) { ramp in
                    TVRampCard(ramp: ramp)
                }
            }
        }
    }

    // MARK: - Tide Section

    private var tideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "water.waves")
                Text("Tide")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let tide = viewModel.tideInfo {
                    HStack(spacing: 4) {
                        Image(systemName: tide.isRising ? "arrow.up.right" : "arrow.down.right")
                        Text("\(tide.tideDirection) \(tide.tidePercentage)%")
                    }
                    .font(.headline)
                }
            }
            .foregroundStyle(.white)

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
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.hour())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
            }

            // Predictions
            if let preds = viewModel.tideInfo?.predictions, !preds.isEmpty {
                HStack(spacing: 16) {
                    ForEach(preds) { pred in
                        VStack(spacing: 2) {
                            Text(pred.label)
                                .font(.caption.weight(.bold))
                            Text(pred.timeDisplay)
                                .font(.caption2)
                                .opacity(0.7)
                        }
                        .foregroundStyle(pred.type == "H" ? .white : .white.opacity(0.7))
                    }
                }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.1))
        }
    }

    // MARK: - Weather Section

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud.sun.fill")
                Text("Weather")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let current = viewModel.weather?.current {
                    Text(current.tempDisplay)
                        .font(.system(size: 36, weight: .light))
                }
            }
            .foregroundStyle(.white)

            if let current = viewModel.weather?.current {
                HStack(spacing: 20) {
                    if let desc = current.description {
                        Label(desc, systemImage: "cloud")
                            .font(.body)
                    }
                    Label(current.windDisplay, systemImage: "wind")
                        .font(.body)
                    if let gust = current.gustDisplay {
                        Text(gust)
                            .font(.body)
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
            }

            // Forecast row
            if let forecast = viewModel.weather?.forecast {
                let daytime = forecast.filter(\.isDaytime).prefix(4)
                HStack(spacing: 16) {
                    ForEach(Array(daytime)) { period in
                        VStack(spacing: 4) {
                            Text(period.shortName)
                                .font(.caption.weight(.semibold))
                                .opacity(0.7)
                            Text(period.tempDisplay)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
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
        HStack(spacing: 16) {
            Image(systemName: ramp.category.tvIcon)
                .font(.title3)
                .foregroundStyle(ramp.category.tvColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(ramp.rampName.titleCased)
                    .font(.headline)
                    .lineLimit(1)
                Text(ramp.locationDisplay)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }

            Spacer()

            Text(ramp.accessStatus.titleCased)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ramp.category.tvColor)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.08))
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  BeachRamp
//
//  Created by Don Browning on 3/10/26.
//

import SwiftUI
import BeachStatus

/// Main content view — shows the beach ramp dashboard.
///
/// On iPhone this is a single scrollable column.
/// On iPad in landscape it uses a two-column layout
/// with ramp list on the left and details on the right.
struct ContentView: View {
    @State private var viewModel = BeachViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad / wide layout — two columns
                iPadLayout
            } else {
                // iPhone / compact layout — single scroll
                iPhoneLayout
            }
        }
        .task {
            await viewModel.loadAll()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                HeaderView(viewModel: viewModel)

                FilterBarView(viewModel: viewModel)
                    .padding(.top, 4)

                // Status summary
                statusSummary

                // Ramp list
                rampList

                // Tide chart
                TideChartView(chartData: viewModel.tideChart, tideInfo: viewModel.tideInfo)
                    .padding(.horizontal)

                // Weather forecast
                WeatherSectionView(weather: viewModel.weather)
                    .padding(.horizontal)

                // Water temperature
                WaterTempView(tideInfo: viewModel.tideInfo)
                    .padding(.horizontal)

                // Webcam
                WebcamView(webcamURL: viewModel.webcamURL)
                    .padding(.horizontal)

                // Footer spacer
                Color.clear.frame(height: 20)
            }
        }
        .background(backgroundGradient)
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Left column — ramps
            ScrollView {
                LazyVStack(spacing: 16) {
                    HeaderView(viewModel: viewModel)
                    FilterBarView(viewModel: viewModel)
                    statusSummary
                    rampList
                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right column — details
            ScrollView {
                LazyVStack(spacing: 16) {
                    TideChartView(chartData: viewModel.tideChart, tideInfo: viewModel.tideInfo)
                        .padding(.horizontal)
                        .padding(.top)

                    WeatherSectionView(weather: viewModel.weather)
                        .padding(.horizontal)

                    WaterTempView(tideInfo: viewModel.tideInfo)
                        .padding(.horizontal)

                    WebcamView(webcamURL: viewModel.webcamURL)
                        .padding(.horizontal)

                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(backgroundGradient)
    }

    // MARK: - Shared Components

    private var statusSummary: some View {
        HStack(spacing: 16) {
            StatusCount(count: viewModel.openCount, label: "Open", color: .statusOpen)
            StatusCount(count: viewModel.limitedCount, label: "Limited", color: .statusLimited)
            StatusCount(count: viewModel.closedCount, label: "Closed", color: .statusClosed)
        }
        .padding(.horizontal)
    }

    private var rampList: some View {
        Group {
            if viewModel.isLoading && viewModel.ramps.isEmpty {
                ProgressView("Loading ramps…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.filteredRamps.isEmpty {
                ContentUnavailableView {
                    Label("No Ramps", systemImage: "beach.umbrella")
                } description: {
                    Text("No ramps match your current filters.")
                }
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.filteredRamps) { ramp in
                    RampCardView(ramp: ramp)
                        .padding(.horizontal)
                }
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private var backgroundGradient: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

/// Small circle count indicator for status summary.
struct StatusCount: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.cardBackground)
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  BeachRampWatch Watch App
//
//  Created by Don Browning on 3/11/26.
//

import SwiftUI
import BeachStatus

/// Main watch view — glance-style NSB ramp list with drill-down to all ramps.
struct ContentView: View {
    @State private var viewModel = WatchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.ramps.isEmpty {
                    ProgressView("Loading…")
                } else if viewModel.displayedRamps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "beach.umbrella")
                            .font(.title2)
                        Text("No ramps available")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    rampList
                }
            }
            .navigationTitle("Beach Ramps")
            .task {
                await viewModel.loadAll()
            }
        }
    }

    private var rampList: some View {
        List {
            // Status summary header
            Section {
                HStack(spacing: 12) {
                    StatusDot(count: viewModel.openCount, color: .watchStatusOpen)
                    StatusDot(count: viewModel.limitedCount, color: .watchStatusLimited)
                    StatusDot(count: viewModel.closedCount, color: .watchStatusClosed)
                }
                .listRowBackground(Color.clear)
            }

            // Ramp rows
            Section {
                ForEach(viewModel.displayedRamps) { ramp in
                    WatchRampRow(ramp: ramp)
                }
            } header: {
                Text(viewModel.showAllCities ? "All Cities" : viewModel.defaultCity)
            }

            // Toggle to show all cities
            Section {
                Button {
                    viewModel.showAllCities.toggle()
                } label: {
                    HStack {
                        Image(systemName: viewModel.showAllCities ? "line.3.horizontal.decrease.circle.fill" : "globe")
                        Text(viewModel.showAllCities ? "Show \(viewModel.defaultCity)" : "Show All Cities")
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

/// Single ramp row for the watch list.
struct WatchRampRow: View {
    let ramp: Ramp

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ramp.category.iconName)
                .foregroundStyle(ramp.category.watchColor)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(ramp.rampName.titleCased)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)

                Text(ramp.accessStatus.titleCased)
                    .font(.caption2)
                    .foregroundStyle(ramp.category.watchColor)
            }
        }
    }
}

/// Compact status count with colored dot.
struct StatusDot: View {
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}

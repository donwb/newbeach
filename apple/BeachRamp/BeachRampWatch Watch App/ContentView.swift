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
            .navigationTitle("Beach Info")
            .task {
                await viewModel.loadAll()
            }
        }
    }

    private var rampList: some View {
        List {
            // Status summary header
            Section {
                HStack(spacing: 8) {
                    StatusDot(count: viewModel.openCount, label: "Open", color: .watchStatusOpen)
                    StatusDot(count: viewModel.limitedCount, label: "Ltd", color: .watchStatusLimited)
                    StatusDot(count: viewModel.closedCount, label: "Closed", color: .watchStatusClosed)
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
        .refreshable {
            await viewModel.refresh()
        }
    }
}

/// Single ramp row for the watch list.
struct WatchRampRow: View {
    let ramp: Ramp

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ramp.category.iconName)
                .foregroundStyle(ramp.category.watchColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(ramp.rampName.titleCased)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)

                Text(ramp.accessStatus.titleCased)
                    .font(.caption2)
                    .foregroundStyle(ramp.category.watchColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Compact status count with colored fill — rounded numerals to echo the other apps.
struct StatusDot: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.15))
        }
    }
}

#Preview {
    ContentView()
}

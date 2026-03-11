import Foundation
import Observation
import BeachStatus

/// Main view model that drives all data for the Beach Ramp Status app.
@Observable
final class BeachViewModel {
    // MARK: - Published State

    var ramps: [Ramp] = []
    var tideInfo: TideInfo?
    var tideChart: TideChartData?
    var weather: WeatherInfo?
    var config: AppConfig?

    var isLoading = false
    var errorMessage: String?

    /// Current city filter — nil means "All".
    var selectedCity: String?

    /// Current status filter — nil means "All".
    var selectedStatus: StatusCategory?

    // MARK: - Computed

    /// Unique city names from loaded ramps, sorted alphabetically.
    var cities: [String] {
        Array(Set(ramps.map(\.cityDisplay))).sorted()
    }

    /// Ramps filtered by current city and status selection.
    var filteredRamps: [Ramp] {
        ramps.filter { ramp in
            let cityMatch = selectedCity == nil || ramp.cityDisplay == selectedCity
            let statusMatch = selectedStatus == nil || ramp.category == selectedStatus
            return cityMatch && statusMatch
        }
    }

    /// Counts per status category.
    var openCount: Int { ramps.filter { $0.category == .open }.count }
    var limitedCount: Int { ramps.filter { $0.category == .limited }.count }
    var closedCount: Int { ramps.filter { $0.category == .closed }.count }

    /// Webcam image URL from config.
    var webcamURL: URL? {
        guard let urlStr = config?.webcamURL else { return nil }
        return URL(string: urlStr)
    }

    /// Water temperature display.
    var waterTempDisplay: String? {
        guard let avg = tideInfo?.waterTempAvg else { return nil }
        return "\(Int(avg))°F"
    }

    // MARK: - Networking

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fetch all data from the API concurrently.
    @MainActor
    func loadAll() async {
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRamps() }
            group.addTask { await self.loadTides() }
            group.addTask { await self.loadTideChart() }
            group.addTask { await self.loadWeather() }
            group.addTask { await self.loadConfig() }
        }

        // Default to New Smyrna Beach on first load
        if selectedCity == nil {
            let defaultCity = config.map { $0.defaultCity.titleCased } ?? "New Smyrna Beach"
            if cities.contains(defaultCity) {
                selectedCity = defaultCity
            }
        }

        isLoading = false
    }

    /// Refresh all data (for pull-to-refresh).
    @MainActor
    func refresh() async {
        await loadAll()
    }

    // MARK: - Individual Loaders

    @MainActor
    private func loadRamps() async {
        do {
            ramps = try await api.fetchRamps()
        } catch {
            errorMessage = "Failed to load ramps: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadTides() async {
        do {
            tideInfo = try await api.fetchTides()
        } catch {
            errorMessage = "Failed to load tides: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadTideChart() async {
        do {
            tideChart = try await api.fetchTideChart()
        } catch {
            errorMessage = "Failed to load tide chart: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadWeather() async {
        do {
            weather = try await api.fetchWeather()
        } catch {
            errorMessage = "Failed to load weather: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadConfig() async {
        do {
            config = try await api.fetchConfig()
        } catch {
            // Non-critical — config just provides defaults
        }
    }
}

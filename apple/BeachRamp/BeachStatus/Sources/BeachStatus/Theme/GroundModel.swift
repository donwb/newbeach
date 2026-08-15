import Foundation
import Observation
import SwiftUI

/// Everything the sun says about the ground at one instant. Pure value —
/// widgets compute one per timeline entry; the app wraps it in `GroundModel`.
/// Mechanics mirror web/js/sky.js `groundState` exactly.
public struct GroundState: Sendable {
    public let date: Date
    public let palette: SkyPalette
    /// Sun altitude in degrees.
    public let altitude: Double
    public let isRising: Bool
    /// 1 above +8° altitude, 0 below −4° (civil dusk):
    /// `clamp((altitude + 4) / 12, 0, 1)`.
    public let dayness: Double

    /// Foreground tokens flip here rather than interpolating.
    public var isDay: Bool { dayness >= 0.5 }
    public var tokens: TokenSet { isDay ? .day : .night }

    /// The Modernist paper tinted 70% toward the sky's own low color, laid
    /// over the sheet at `dayness` opacity. Past civil dusk it vanishes and
    /// the sky continues through the sheet.
    public var veil: Color {
        let paper = SkyStop(0xF3F2F2)
        let mixed = palette.bottomStop.mixed(with: paper, fraction: 0.70)
        return Color(red: mixed.r, green: mixed.g, blue: mixed.b, opacity: dayness)
    }

    /// The sky as the handoff draws it: 160°, stops at 0 / 46 / 100%.
    public var skyGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: palette.topStop.color, location: 0),
                .init(color: palette.midStop.color, location: 0.46),
                .init(color: palette.bottomStop.color, location: 1),
            ],
            // CSS 160deg: down and slightly right-to-left.
            startPoint: UnitPoint(x: 0.329, y: 0.030),
            endPoint: UnitPoint(x: 0.671, y: 0.970)
        )
    }

    /// Top scrim over the hero so white type holds over the warm horizon band.
    public var heroScrim: LinearGradient {
        let base = Color(token: 0x06202C)
        return LinearGradient(
            stops: [
                .init(color: base.opacity(0.58), location: 0),
                .init(color: base.opacity(0.30), location: 0.46),
                .init(color: base.opacity(0.04), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static func compute(
        at date: Date,
        calculator: SolarCalculator = .newSmyrnaBeach
    ) -> GroundState {
        let altitude = calculator.altitude(at: date)
        let rising = calculator.isRising(at: date)
        return GroundState(
            date: date,
            palette: SkyPalette.forSun(altitude: altitude, isRising: rising),
            altitude: altitude,
            isRising: rising,
            dayness: min(1, max(0, (altitude + 4) / 12))
        )
    }
}

/// The current ground, injected at the app root. Defaults to a computed
/// mid-morning state so previews render sensibly without a model.
private struct GroundStateKey: EnvironmentKey {
    static let defaultValue = GroundState.compute(at: Date())
}

public extension EnvironmentValues {
    var ground: GroundState {
        get { self[GroundStateKey.self] }
        set { self[GroundStateKey.self] = newValue }
    }
}

/// The app's live ground: recomputes `state` on a 30-second tick (the same
/// cadence tvOS uses). Views animate the change over 2s unless Reduce Motion
/// is on — callers own that via `withAnimation`; the model just publishes.
@MainActor
@Observable
public final class GroundModel {
    public private(set) var state: GroundState

    /// QA hook: freeze the ground at a fixed date (night screenshots, phase
    /// review). Nil follows the wall clock.
    public var overrideDate: Date? {
        didSet { refresh() }
    }

    private let calculator: SolarCalculator
    private var timer: Timer?

    public init(calculator: SolarCalculator = .newSmyrnaBeach, overrideDate: Date? = nil) {
        self.calculator = calculator
        self.overrideDate = overrideDate
        state = GroundState.compute(at: overrideDate ?? Date(), calculator: calculator)
    }

    public func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        state = GroundState.compute(at: overrideDate ?? Date(), calculator: calculator)
    }
}

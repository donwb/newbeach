import Foundation

/// Computes solar events (sunrise, sunset) and the sun's current altitude for a
/// fixed geographic location.
///
/// Pure value type — no I/O, no clock dependency beyond the `Date` you pass in —
/// so it's trivially testable. Uses a low-precision sun-position model (good to a
/// fraction of a degree) and finds sunrise/sunset by locating the horizon crossing
/// of that altitude. Accuracy is well within a minute for our purposes: driving a
/// time-of-day background and displaying sun times.
public struct SolarCalculator: Sendable {
    /// Latitude in degrees, north positive.
    public let latitude: Double
    /// Longitude in degrees, east positive (so the US is negative).
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// New Smyrna Beach, FL — the location the dashboard is anchored to.
    public static let newSmyrnaBeach = SolarCalculator(latitude: 29.0258, longitude: -80.9270)

    /// Standard sunrise/sunset altitude: -0.833° accounts for the sun's apparent
    /// radius plus atmospheric refraction at the horizon.
    private static let horizonAltitude = -0.833

    // MARK: - Sun Altitude

    /// The sun's altitude above the horizon, in degrees, at the given instant.
    /// Negative means below the horizon (twilight or night).
    public func altitude(at date: Date = Date()) -> Double {
        let n = julianDate(date) - 2451545.0 // days since J2000.0

        let meanLongitude = normalizeDegrees(280.460 + 0.9856474 * n)
        let meanAnomaly = normalizeDegrees(357.528 + 0.9856003 * n)
        let eclipticLongitude = meanLongitude
            + 1.915 * sin(rad(meanAnomaly))
            + 0.020 * sin(rad(2 * meanAnomaly))
        let obliquity = 23.439 - 0.0000004 * n

        let declination = asin(sin(rad(obliquity)) * sin(rad(eclipticLongitude)))
        let rightAscension = atan2(
            cos(rad(obliquity)) * sin(rad(eclipticLongitude)),
            cos(rad(eclipticLongitude))
        )

        let gmst = normalizeDegrees(280.46061837 + 360.98564736629 * n)
        let localSiderealTime = rad(gmst + longitude)
        let hourAngle = localSiderealTime - rightAscension

        let lat = rad(latitude)
        let sinAltitude = sin(lat) * sin(declination)
            + cos(lat) * cos(declination) * cos(hourAngle)
        return deg(asin(min(1, max(-1, sinAltitude))))
    }

    /// Whether the sun is climbing (morning) at the given instant. Compares the
    /// altitude a few minutes on either side, so it's robust near the horizon.
    public func isRising(at date: Date = Date()) -> Bool {
        altitude(at: date.addingTimeInterval(300)) > altitude(at: date.addingTimeInterval(-300))
    }

    // MARK: - Sunrise / Sunset

    /// Sunrise and sunset for the calendar day containing `date`, evaluated in
    /// `calendar`'s time zone. Components are absolute instants — format them in
    /// whatever zone you display. Returns `nil` for an event that doesn't occur
    /// (polar day/night); not a concern in Florida, but handled for safety.
    public func events(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> (sunrise: Date?, sunset: Date?) {
        let startOfDay = calendar.startOfDay(for: date)
        let step: TimeInterval = 300 // 5-minute coarse scan, refined by bisection
        let horizon = Self.horizonAltitude

        var sunrise: Date?
        var sunset: Date?
        var prevTime = startOfDay
        var prevAltitude = altitude(at: startOfDay)

        var offset = step
        while offset <= 86_400 {
            let time = startOfDay.addingTimeInterval(offset)
            let alt = altitude(at: time)

            if sunrise == nil, prevAltitude < horizon, alt >= horizon {
                sunrise = refineCrossing(from: prevTime, to: time, rising: true)
            }
            if sunset == nil, prevAltitude >= horizon, alt < horizon {
                sunset = refineCrossing(from: prevTime, to: time, rising: false)
            }

            prevTime = time
            prevAltitude = alt
            offset += step
        }
        return (sunrise, sunset)
    }

    /// Bisects a horizon crossing bracketed by `[from, to]` to sub-second precision.
    private func refineCrossing(from: Date, to: Date, rising: Bool) -> Date {
        var low = from
        var high = to
        for _ in 0..<24 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            let above = altitude(at: mid) >= Self.horizonAltitude
            if above == rising {
                high = mid
            } else {
                low = mid
            }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    // MARK: - Helpers

    private func julianDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    private func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private func deg(_ radians: Double) -> Double { radians * 180 / .pi }
}

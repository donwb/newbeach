import Foundation

/// Changes the channel when the cam picture goes black and stays black.
///
/// The county's feeds sometimes go to a black picture, and a player stuck on
/// one rarely finds its way back by rebuilding — but the same cam is fine a
/// few minutes later if the viewer flips away and back. So the players read
/// their own picture (`CamPictureSampler`) and feed it here; after
/// `patience` of black this names the next cam in roster order.
///
/// The clock runs per cam, not per player: a failure rebuild replaces the
/// player every ~10s while the cam is dark, and resetting on each rebuild
/// would mean the switch never came. Callers `restart()` it whenever a
/// different cam goes on screen.
///
/// Guards against flipping forever: cams already left black this sweep, and
/// cams the relay reports offline, are never switched to; when no candidate
/// is left the watch stays put and rests before another sweep. Any lit
/// picture ends the sweep. At night it does nothing — a dark beach is not a
/// dead feed.
public struct CamDarkWatch: Sendable {
    /// How long the picture must stay black before switching.
    public static let patience: TimeInterval = 10
    /// After a sweep finds every cam black, wait this long before another.
    public static let restAfterSweep: TimeInterval = 120
    /// Sun altitude below which the watch stands down (civil dusk).
    static let nightAltitude: Double = -6

    private var darkSince: Date?
    private var skipped: Set<String> = []
    private var restUntil: Date?
    private let solar: SolarCalculator

    public init(solar: SolarCalculator = .newSmyrnaBeach) {
        self.solar = solar
    }

    /// A different cam is on screen; its black clock starts fresh. The sweep
    /// (cams already left black) carries over.
    public mutating func restart() {
        darkSince = nil
    }

    /// One reading of the picture on screen while `current` plays. Returns
    /// the cam to switch to once the picture has been black for `patience`,
    /// or nil to stay.
    public mutating func note(lit: Bool, watching current: String,
                              roster: [Camera], at now: Date) -> String? {
        if lit {
            darkSince = nil
            skipped.removeAll()
            restUntil = nil
            return nil
        }
        if solar.altitude(at: now) < Self.nightAltitude {
            darkSince = nil
            return nil
        }
        if let rest = restUntil {
            if now < rest { return nil }
            restUntil = nil
        }
        guard let since = darkSince else {
            darkSince = now
            return nil
        }
        guard now.timeIntervalSince(since) >= Self.patience else { return nil }

        darkSince = nil
        skipped.insert(current)
        if let next = Self.next(after: current, in: roster, skipping: skipped) {
            return next
        }
        // Every cam is black or offline: stay, rest, then try a fresh sweep.
        skipped.removeAll()
        restUntil = now.addingTimeInterval(Self.restAfterSweep)
        return nil
    }

    /// The next cam after `current` in roster order (wrapping), passing over
    /// skipped cams, cams with no stream, and cams the relay reports offline.
    static func next(after current: String, in roster: [Camera],
                     skipping skipped: Set<String>) -> String? {
        guard !roster.isEmpty else { return nil }
        let start = roster.firstIndex { $0.id == current } ?? -1
        for step in 1...roster.count {
            let cam = roster[(start + step) % roster.count]
            if cam.id == current || skipped.contains(cam.id) { continue }
            if cam.url == nil || cam.online == false { continue }
            return cam.id
        }
        return nil
    }
}

/// Reads whether a decoded frame shows a picture or a black screen.
public enum CamPicture {
    /// Full-range luma at or below this reads as black. Daytime cams sample
    /// around 130 on average with minimums near 80 (2026-10-09).
    static let blackLuma: Int = 24
    /// Share of samples that must be black for the frame to count. Below 1 so
    /// a burned-in overlay (logo, timestamp) on a dead feed still reads black.
    static let blackShare: Double = 0.97

    /// True when the frame is (almost) entirely black. `videoRange` luma runs
    /// 16–235 and is normalized to full range first.
    public static func isBlack(luma samples: [UInt8], videoRange: Bool) -> Bool {
        guard !samples.isEmpty else { return false }
        var black = 0
        for y in samples {
            let level = videoRange ? (Int(y) - 16) * 255 / 219 : Int(y)
            if level <= blackLuma { black += 1 }
        }
        return Double(black) / Double(samples.count) >= blackShare
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Observation

/// The cam still fallback: YouTube's live thumbnail of the same broadcast,
/// shown when a cam's relay stream is dark (the restreamer can't always pull
/// video — see docs/CAM-RELAY.md). The server derives the URL (`still_url` on
/// the roster); YouTube refreshes the frame every ~4–6 minutes and serves it
/// to any IP.
///
/// The thumbnail is 1280×720 with the cam's 1280×270 panorama letterboxed in
/// the middle (rows 225–494, measured 2026-11-23 on every cam). `band(from:)`
/// crops it back out so the still lines up pixel for pixel with the video and
/// the clients' existing crop (e.g. the tvOS badge trim) applies unchanged.
public enum CamStill {
    /// The relay panorama's aspect (1280×270).
    public static let panoramaAspect: Double = 1280.0 / 270.0

    /// What a fetched thumbnail holds.
    public enum Frame {
        /// A lit picture, cropped to the panorama band.
        case lit(CGImage)
        /// A black frame: the county's camera is dead (Ormond-By-The-Sea on
        /// 2026-11-23) or the beach is dark. Show the plain dark field.
        case dark
    }

    /// Crop the panorama band out of a letterboxed thumbnail and read it lit
    /// or black with the same rule the live players use (`CamPicture`).
    /// Returns nil when the data isn't a decodable image.
    public static func band(from data: Data) -> Frame? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return band(from: image)
    }

    static func band(from image: CGImage) -> Frame? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        // Centered band at the panorama's aspect; a frame already that wide
        // (or wider) is used whole.
        let bandHeight = min(height, Int((Double(width) / panoramaAspect).rounded()))
        let rect = CGRect(x: 0, y: (height - bandHeight) / 2,
                          width: width, height: bandHeight)
        guard let band = image.cropping(to: rect) else { return nil }
        return isBlack(band) ? .dark : .lit(band)
    }

    /// Downsample to a small grayscale grid and apply `CamPicture.isBlack`.
    static func isBlack(_ image: CGImage) -> Bool {
        let cols = 64, rows = 16
        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: cols, height: rows,
                bitsPerComponent: 8, bytesPerRow: cols,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            return true
        }
        guard drawn else { return false }
        return CamPicture.isBlack(luma: pixels, videoRange: false)
    }

    /// The URL with a minute-granular cache-buster. The thumbnail is served
    /// `max-age=300`, which on top of YouTube's own ~5-minute refresh would
    /// let a device show a frame ~10 minutes old.
    public static func freshURL(_ url: URL, at now: Date = Date()) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        let stamp = URLQueryItem(name: "t", value: String(Int(now.timeIntervalSince1970) / 60))
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "t" } + [stamp]
        return parts.url ?? url
    }
}

/// Keeps one cam's still current: fetches on `show(_:)` and every
/// `refreshInterval` after, holding the last good frame through a failed
/// fetch so the picture never blinks to empty over a network hiccup.
@MainActor
@Observable
public final class CamStillLoader {
    /// The latest lit band, or nil (nothing loaded yet, or the frame is black).
    public private(set) var image: CGImage?
    /// True when the latest frame read black.
    public private(set) var isDark = false
    /// The still currently being kept fresh.
    public private(set) var url: URL?

    /// YouTube refreshes every ~4–6 min; two-minute polls catch each new
    /// frame within ~2 min without hammering an image CDN.
    public static let refreshInterval: TimeInterval = 120

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Start keeping `url` fresh (nil stops). The same URL again is a no-op,
    /// so callers can call this on every roster refresh.
    public func show(_ url: URL?) {
        guard url != self.url else { return }
        task?.cancel()
        self.url = url
        image = nil
        isDark = false
        guard let url else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch(url)
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    public func stop() { show(nil) }

    private func fetch(_ url: URL) async {
        var request = URLRequest(url: CamStill.freshURL(url))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !Task.isCancelled, url == self.url,
              let frame = CamStill.band(from: data)
        else { return }  // keep the last good frame
        switch frame {
        case .lit(let band):
            image = band
            isDark = false
        case .dark:
            image = nil
            isDark = true
        }
    }
}

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
        /// A dead feed: the county's encoder is sending a flat near-black
        /// field (Ormond-By-The-Sea on 2026-11-23). Show the plain dark field.
        /// A night frame is *not* this — see `isDeadFeed`.
        case dark
    }

    /// Crop the panorama band out of a letterboxed thumbnail and read it lit
    /// or dead (`isDeadFeed`). Returns nil when the data isn't a decodable
    /// image.
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
        return isDeadFeed(band) ? .dark : .lit(band)
    }

    /// Luma a pixel must reach to count as something lit. The dead
    /// Ormond-By-The-Sea frame peaks at 22 (2026-11-23); a lit day frame runs
    /// 130–190.
    static let litLuma: UInt8 = 64
    /// Lit pixels needed before the frame counts as showing anything.
    static let litPixels = 24

    /// True only for a dead feed: no spot in the frame is lit at all.
    ///
    /// Deliberately not `CamPicture.isBlack` (97% of samples black), which is
    /// right for the live players' "switch away from a black feed" watch but
    /// wrong here. A night still is mostly black too, yet it is worth showing:
    /// condo and pier lights, a bright moon on the water (Don, 2026-11-23).
    /// A live encoder also burns in the AccuWeather badge, which is bright at
    /// any hour. So: render at native size, no downsampling (that would
    /// average a few-pixel light into the dark), and call it dead only when
    /// fewer than `litPixels` reach `litLuma`.
    static func isDeadFeed(_ image: CGImage) -> Bool {
        // Cap the work for oversized frames; the thumbnail band is 1280×270.
        let scale = min(1, 1280 / Double(image.width))
        let cols = max(1, Int(Double(image.width) * scale))
        let rows = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: cols, height: rows,
                bitsPerComponent: 8, bytesPerRow: cols,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            return true
        }
        guard drawn else { return false }
        var lit = 0
        for y in pixels where y >= litLuma {
            lit += 1
            if lit >= litPixels { return false }
        }
        return true
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

    #if DEBUG
    /// Previews: show a frame without fetching anything.
    public func preview(_ url: URL?, image: CGImage?, dark: Bool = false) {
        task?.cancel()
        self.url = url
        self.image = image
        isDark = dark
    }
    #endif

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

#if DEBUG
extension CamStill {
    /// A 1280×270 sky/water/sand gradient standing in for a still in previews.
    public static let previewBand: CGImage = {
        let width = 1280, height = 270
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.62, green: 0.74, blue: 0.86, alpha: 1),   // sky
                      CGColor(red: 0.42, green: 0.56, blue: 0.66, alpha: 1),   // water
                      CGColor(red: 0.80, green: 0.74, blue: 0.62, alpha: 1)]   // sand
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.45, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)),
                                   end: .zero, options: [])
        return context.makeImage()!
    }()
}
#endif

/// What a cam surface is showing, for the LIVE / STILL indicator every
/// platform carries next to the picture.
public enum CamMode: Equatable, Sendable {
    /// The relay is streaming: real video.
    case live
    /// No live video; the still fallback stands in.
    case still
    /// Neither: no stream and no usable still (none offered, or a dead feed).
    case offline

    /// The mode for `camera`, given whether its latest still read as a dead
    /// feed (`CamStillLoader.isDark`; pass false when it isn't known).
    public static func of(_ camera: Camera?, stillDead: Bool = false) -> CamMode {
        guard let camera else { return .offline }
        if camera.hasLiveVideo { return .live }
        if camera.stillImageURL != nil && !stillDead { return .still }
        return .offline
    }
}

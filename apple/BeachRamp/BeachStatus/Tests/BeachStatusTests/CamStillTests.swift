import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BeachStatus

/// A gray test frame: `fill` everywhere, `band` luma over rows `bandRows`
/// (top-down, like the thumbnails).
private func frame(width: Int = 1280, height: Int = 720, fill: UInt8 = 0,
                   band: UInt8? = nil, bandRows: Range<Int> = 225..<495) -> CGImage {
    var pixels = [UInt8](repeating: fill, count: width * height)
    if let band {
        for row in bandRows {
            for col in 0..<width { pixels[row * width + col] = band }
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

private func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

@Suite("CamStill")
struct CamStillTests {
    @Test("a letterboxed live thumbnail crops to the 1280×270 panorama")
    func cropsLetterboxedBand() throws {
        guard case .lit(let band) = CamStill.band(from: frame(band: 140)) else {
            Issue.record("expected a lit band"); return
        }
        #expect(band.width == 1280)
        #expect(band.height == 270)
    }

    @Test("the crop lands on the picture, not the bars")
    func cropIsCentered() throws {
        // Picture only in the band: if the crop were off-center it would pull
        // in black bar rows and the band would still read lit, so check that
        // a frame lit only *outside* the band reads dark.
        let barsOnly = frame(fill: 0, band: 200, bandRows: 0..<200)
        guard case .dark = CamStill.band(from: barsOnly) else {
            Issue.record("bars-only frame should read dark"); return
        }
    }

    @Test("a dead feed's near-black frame reads dark")
    func deadFeedIsDark() {
        // Ormond-By-The-Sea, 2026-11-23: a uniform ~#111 noise field.
        guard case .dark = CamStill.band(from: frame(fill: 17)) else {
            Issue.record("expected dark"); return
        }
    }

    @Test("a panorama-or-wider image is used whole")
    func widerThanPanorama() {
        guard case .lit(let band) = CamStill.band(from: frame(width: 1280, height: 200, fill: 120)) else {
            Issue.record("expected lit"); return
        }
        #expect(band.height == 200)
    }

    @Test("decodes encoded image data; rejects garbage")
    func decodesData() {
        guard case .lit = CamStill.band(from: png(frame(band: 140))) else {
            Issue.record("expected lit from PNG data"); return
        }
        #expect(CamStill.band(from: Data("not an image".utf8)) == nil)
    }

    @Test("cache-buster is minute-granular and replaces an existing stamp")
    func freshURL() {
        let base = URL(string: "https://i.ytimg.com/vi/550p9smwjPM/maxresdefault_live.jpg")!
        let now = Date(timeIntervalSince1970: 1_795_000_020)  // on a minute boundary
        let fresh = CamStill.freshURL(base, at: now)
        #expect(fresh.absoluteString == base.absoluteString + "?t=29916667")
        #expect(CamStill.freshURL(base, at: now.addingTimeInterval(30)) == fresh)
        #expect(CamStill.freshURL(fresh, at: now) == fresh)
    }
}

@Suite("Camera still + live video")
struct CameraStillDecodingTests {
    private func decode(_ json: String) throws -> Camera {
        try JSONDecoder().decode(Camera.self, from: Data(json.utf8))
    }

    @Test("still_url decodes; older payloads without it decode to nil")
    func stillURL() throws {
        let with = try decode(#"{"id":"nsb","name":"NSB","location":"NSB","stream_url":"https://cams.donwb.com/nsb/index.m3u8","still_url":"https://i.ytimg.com/vi/550p9smwjPM/maxresdefault_live.jpg"}"#)
        #expect(with.stillImageURL?.host == "i.ytimg.com")
        let without = try decode(#"{"id":"nsb","name":"NSB","location":"NSB","stream_url":""}"#)
        #expect(without.stillURL == nil)
        #expect(without.stillImageURL == nil)
    }

    @Test("live video needs a stream the relay hasn't reported dark",
          arguments: [
            ("https://cams.donwb.com/nsb/index.m3u8", Bool?.none, true),
            ("https://cams.donwb.com/nsb/index.m3u8", Bool?.some(true), true),
            ("https://cams.donwb.com/nsb/index.m3u8", Bool?.some(false), false),
            ("", Bool?.some(true), false),
          ])
    func hasLiveVideo(stream: String, online: Bool?, expected: Bool) {
        let cam = Camera(id: "nsb", name: "NSB", location: "NSB", streamURL: stream, online: online)
        #expect(cam.hasLiveVideo == expected)
    }
}

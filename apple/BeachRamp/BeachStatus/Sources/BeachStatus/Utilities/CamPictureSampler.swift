#if !os(watchOS)
import AVFoundation
import CoreVideo
import QuartzCore

/// Reads the picture a cam player is actually showing, every two seconds,
/// and reports lit (true) or black (false) for `CamDarkWatch`.
///
/// Until the first frame decodes the layer is empty, so that reads black
/// too — a rebuilt player that never gets a picture is exactly the stuck
/// case. When frames stop arriving the layer holds the last one, so the
/// last frame's reading stands. One sampler per AVPlayerItem; drop it with
/// the player.
public final class CamPictureSampler {
    private static let interval: TimeInterval = 2
    /// The vendor's AccuWeather badge sits in the top ~13% of the frame
    /// (see PictureBand); skip it so it can't light up a dead picture.
    private static let skipTopShare = 0.15

    private let output: AVPlayerItemVideoOutput
    private weak var item: AVPlayerItem?
    private var timer: Timer?
    private var lastLit = false
    private let onSample: (Bool) -> Void

    public init(item: AVPlayerItem, onSample: @escaping (Bool) -> Void) {
        self.item = item
        self.onSample = onSample
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        item.add(output)

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        item?.remove(output)
    }

    private func tick() {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
           let lit = Self.read(buffer) {
            lastLit = lit
        }
        onSample(lastLit)
    }

    /// Lit/black for one frame, or nil for a pixel format it can't read.
    private static func read(_ buffer: CVPixelBuffer) -> Bool? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let videoRange: Bool
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: videoRange = false
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: videoRange = true
        default: return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        // A coarse grid is plenty to tell a picture from a black screen.
        var samples: [UInt8] = []
        samples.reserveCapacity((width / 8 + 1) * (height / 4 + 1))
        for row in stride(from: Int(Double(height) * skipTopShare), to: height, by: 4) {
            for col in stride(from: 0, to: width, by: 8) {
                samples.append(luma[row * rowBytes + col])
            }
        }
        return !CamPicture.isBlack(luma: samples, videoRange: videoRange)
    }
}
#endif

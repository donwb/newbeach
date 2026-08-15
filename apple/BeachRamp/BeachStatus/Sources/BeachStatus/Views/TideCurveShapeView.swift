import SwiftUI

/// The curve itself: tidefill under a 2px ink stroke, 2px accent now-line,
/// and (on the ramp detail) a dashed amber line at the ramp's closure height.
public struct TideCurveShapeView: View {
    public let points: [TideCurve.Point]
    public let range: ClosedRange<Date>
    public let height: CGFloat
    /// Closure threshold in feet — the dashed line is the point of the
    /// detail chart. Nil draws nothing.
    public var threshold: Double?
    @Environment(\.ground) private var ground

    public init(points: [TideCurve.Point], range: ClosedRange<Date>,
                height: CGFloat, threshold: Double? = nil) {
        self.points = points
        self.range = range
        self.height = height
        self.threshold = threshold
    }

    public var body: some View {
        let t = ground.tokens
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                fillPath(in: size).fill(t.tideFill)
                strokePath(in: size).stroke(t.ink, lineWidth: 2)
                if let threshold {
                    Path { p in
                        let ty = y(for: threshold, in: size)
                        p.move(to: CGPoint(x: 0, y: ty))
                        p.addLine(to: CGPoint(x: size.width, y: ty))
                    }
                    .stroke(Color(red: 0xF5 / 255, green: 0xA2 / 255, blue: 0x14 / 255),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
                Rectangle()
                    .fill(t.accent)
                    .frame(width: 2)
                    .offset(x: x(for: Date(), in: size) - 1)
            }
        }
        .frame(height: height)
    }

    private var heights: (min: Double, max: Double) {
        var values = points.map(\.height)
        if let threshold { values.append(threshold) }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        // Pad so the curve never kisses the frame edges.
        let pad = max(0.3, (hi - lo) * 0.12)
        return (lo - pad, hi + pad)
    }

    private func x(for time: Date, in size: CGSize) -> CGFloat {
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let t = time.timeIntervalSince(range.lowerBound) / total
        return CGFloat(min(max(t, 0), 1)) * size.width
    }

    private func y(for height: Double, in size: CGSize) -> CGFloat {
        let (lo, hi) = heights
        let t = (height - lo) / (hi - lo)
        return (1 - CGFloat(t)) * size.height
    }

    private func strokePath(in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: x(for: first.time, in: size), y: y(for: first.height, in: size)))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: x(for: point.time, in: size), y: y(for: point.height, in: size)))
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        var path = strokePath(in: size)
        guard let last = points.last, let first = points.first else { return path }
        path.addLine(to: CGPoint(x: x(for: last.time, in: size), y: size.height))
        path.addLine(to: CGPoint(x: x(for: first.time, in: size), y: size.height))
        path.closeSubpath()
        return path
    }
}

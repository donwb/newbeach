import SwiftUI

/// A high or low turn drawn on the curve: a dot, plus an optional caption
/// (above a high, below a low) the caller formats — e.g. "9:05am".
public struct TideCurveMarker: Equatable, Sendable {
    public let time: Date
    public let height: Double
    public let isHigh: Bool
    public let label: String?

    public init(time: Date, height: Double, isHigh: Bool, label: String? = nil) {
        self.time = time
        self.height = height
        self.isHigh = isHigh
        self.label = label
    }
}

/// The curve itself: tidefill under a 2px ink stroke, 2px accent now-line,
/// and (on the ramp detail) a dashed amber line at the ramp's closure height.
/// Optionally: a dashed overlay curve (tomorrow's tide on today's axis) and
/// high/low markers with time captions.
public struct TideCurveShapeView: View {
    public let points: [TideCurve.Point]
    public let range: ClosedRange<Date>
    public let height: CGFloat
    /// Closure threshold in feet — the dashed line is the point of the
    /// detail chart. Nil draws nothing.
    public var threshold: Double?
    /// Curve stroke width — the tvOS detail surface draws at 3.
    public var strokeWidth: CGFloat
    /// Optional color overrides. Nil (the default) reads the `\.ground`
    /// tokens as ever; the tvOS detail surface passes its own mono palette,
    /// where the now-line must not be the ground accent (red means closed
    /// there, and nothing else).
    public var strokeColor: Color?
    public var fillColor: Color?
    public var nowLineColor: Color?
    /// Where the now-line is drawn. A stored input on purpose: computing
    /// Date() inside the draw closure froze the line on long-lived screens —
    /// SwiftUI skips re-rendering when the view's stored inputs are all
    /// equal, and a hidden clock read isn't an input. The default captures
    /// Date() at construction, so the field changes every time a caller's
    /// body runs; tickers (the tvOS board) pass their own clock explicitly.
    public var now: Date
    /// A second curve on the same axis and scale, drawn dashed with no fill —
    /// tomorrow's tide on tvOS. Empty draws nothing.
    public var overlayPoints: [TideCurve.Point]
    public var overlayColor: Color?
    /// High/low turns. Labeled markers reserve `labelBand` points above and
    /// below the plot so captions never clip at the frame edge.
    public var markers: [TideCurveMarker]
    public var markerFont: Font
    public var markerLabelColor: Color?
    public var labelBand: CGFloat
    @Environment(\.ground) private var ground

    public init(points: [TideCurve.Point], range: ClosedRange<Date>,
                height: CGFloat, threshold: Double? = nil,
                strokeWidth: CGFloat = 2, strokeColor: Color? = nil,
                fillColor: Color? = nil, nowLineColor: Color? = nil,
                now: Date = Date(),
                overlayPoints: [TideCurve.Point] = [],
                overlayColor: Color? = nil,
                markers: [TideCurveMarker] = [],
                markerFont: Font = .caption,
                markerLabelColor: Color? = nil,
                labelBand: CGFloat = 28) {
        self.points = points
        self.range = range
        self.height = height
        self.threshold = threshold
        self.strokeWidth = strokeWidth
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.nowLineColor = nowLineColor
        self.now = now
        self.overlayPoints = overlayPoints
        self.overlayColor = overlayColor
        self.markers = markers
        self.markerFont = markerFont
        self.markerLabelColor = markerLabelColor
        self.labelBand = labelBand
    }

    public var body: some View {
        let t = ground.tokens
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                fillPath(in: size).fill(fillColor ?? t.tideFill)
                strokePath(in: size).stroke(strokeColor ?? t.ink, lineWidth: strokeWidth)
                if !overlayPoints.isEmpty {
                    linePath(overlayPoints, in: size)
                        .stroke(overlayColor ?? (strokeColor ?? t.ink).opacity(0.55),
                                style: StrokeStyle(lineWidth: max(1.5, strokeWidth - 1),
                                                   lineCap: .round,
                                                   dash: [strokeWidth * 3, strokeWidth * 3]))
                }
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
                    .fill(nowLineColor ?? t.accent)
                    .frame(width: 2)
                    .offset(x: x(for: now, in: size) - 1)
                ForEach(markers, id: \.time) { marker in
                    markerView(marker, color: strokeColor ?? t.ink,
                               labelColor: markerLabelColor ?? strokeColor ?? t.ink,
                               in: size)
                }
            }
        }
        .frame(height: height)
    }

    private var heights: (min: Double, max: Double) {
        var values = points.map(\.height) + overlayPoints.map(\.height)
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

    /// Vertical room held for captions, top and bottom.
    private var band: CGFloat {
        markers.contains { $0.label != nil } ? labelBand : 0
    }

    private func y(for height: Double, in size: CGSize) -> CGFloat {
        let (lo, hi) = heights
        let t = (height - lo) / (hi - lo)
        return band + (1 - CGFloat(t)) * (size.height - 2 * band)
    }

    @ViewBuilder
    private func markerView(_ marker: TideCurveMarker, color: Color,
                            labelColor: Color, in size: CGSize) -> some View {
        let mx = x(for: marker.time, in: size)
        let my = y(for: marker.height, in: size)
        let dot: CGFloat = strokeWidth * 3 + 2
        Circle()
            .fill(color)
            .frame(width: dot, height: dot)
            .position(x: mx, y: my)
        if let label = marker.label {
            // Captions sit just outside the curve; the x clamp keeps an
            // early-morning or late-night turn's caption on screen.
            let halfWidth: CGFloat = 70
            Text(label)
                .font(markerFont)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(labelColor)
                .frame(width: halfWidth * 2, height: labelBand)
                .position(x: min(max(mx, halfWidth), size.width - halfWidth),
                          y: marker.isHigh ? my - dot / 2 - labelBand / 2
                                           : my + dot / 2 + labelBand / 2)
        }
    }

    private func strokePath(in size: CGSize) -> Path {
        linePath(points, in: size)
    }

    private func linePath(_ points: [TideCurve.Point], in size: CGSize) -> Path {
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

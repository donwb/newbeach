import SwiftUI
import BeachStatus

/// The full-width status field band: mark, status word, since line, and the
/// forward-looking line — the reason the detail screen exists. The line
/// disappears (never placeholders) when the ramp has no threshold.
struct DetailStatusBand: View {
    let ramp: Ramp
    let projection: ClosureProjection?
    /// 20 on iPhone, 28 in the iPad sheet.
    var statusSize: CGFloat = 20
    @Environment(\.ground) private var ground

    private var field: StatusField {
        StatusField.field(for: ramp.category, isDay: ground.isDay)
    }

    private var statusWord: String {
        switch ramp.category {
        case .open: "Open"
        case .limited: "Limited"
        case .closed: "Closed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Rectangle()
                    .fill(field.mark)
                    .frame(width: 12, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusWord)
                        .font(.archivo(statusSize, weight: .extraBold))
                        .foregroundStyle(field.text)
                    if let since = ramp.statusSince {
                        Text("since \(SinceFormatter.string(from: since))")
                            .font(.archivo(12))
                            .foregroundStyle(field.text2)
                    }
                }
            }
            if let projection {
                Text(projection.line)
                    .font(.archivo(14, weight: .semiBold))
                    .foregroundStyle(field.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(field.fill)
        .overlay(Rectangle().strokeBorder(field.border, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

/// Today's status band: midnight to midnight, one segment per state weighted
/// by duration, with an overhanging ink now-marker.
struct TodayStatusBandView: View {
    let intervals: RampIntervals?
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text("Today".uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)

            if segments.isEmpty {
                Text("No status history yet today.")
                    .font(.archivo(12))
                    .foregroundStyle(t.ink2)
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 2) {
                            ForEach(segments.indices, id: \.self) { i in
                                let seg = segments[i]
                                Rectangle()
                                    .fill(StatusField.field(for: seg.category, isDay: ground.isDay).fill)
                                    .frame(width: max(seg.fraction * (width - CGFloat(segments.count - 1) * 2), 2))
                            }
                        }
                        .frame(height: 18)
                        .padding(.top, 9)
                        // Now-marker, 3px, overhanging 9pt top and bottom.
                        Rectangle()
                            .fill(t.ink)
                            .frame(width: 3, height: 36)
                            .offset(x: nowFraction * width - 1.5)
                    }
                }
                .frame(height: 36)

                // Start time + label under each segment.
                HStack(alignment: .top, spacing: 8) {
                    ForEach(segments.indices, id: \.self) { i in
                        let seg = segments[i]
                        VStack(alignment: .leading, spacing: 1) {
                            Text(SinceFormatter.clock(seg.start))
                                .font(.archivo(12, weight: .extraBold))
                                .monospacedDigit()
                                .foregroundStyle(t.ink)
                            Text(seg.label)
                                .font(.archivo(10))
                                .foregroundStyle(t.ink2)
                        }
                        if i < segments.count - 1 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private struct Segment {
        let category: StatusCategory
        let label: String
        let start: Date
        let fraction: CGFloat
    }

    /// Today's intervals, clipped midnight → now (the band runs to midnight,
    /// but the future is unknown — segments end at now and the remainder of
    /// the day stays empty in the math below by scaling to the full day).
    private var segments: [Segment] {
        guard let intervals else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayLength: TimeInterval = 24 * 3600
        var result: [Segment] = []
        for interval in intervals.intervals {
            let start = max(interval.start, dayStart)
            let end = min(interval.end, dayStart.addingTimeInterval(dayLength))
            guard end > start else { continue }
            result.append(Segment(
                category: interval.statusCategory,
                label: interval.statusCategory == .open ? "Open"
                    : interval.statusCategory == .limited ? "Limited" : "Closed",
                start: start,
                fraction: CGFloat(end.timeIntervalSince(start) / dayLength)
            ))
        }
        return result
    }

    private var nowFraction: CGFloat {
        let dayStart = Calendar.current.startOfDay(for: Date())
        return CGFloat(min(Date().timeIntervalSince(dayStart) / (24 * 3600), 1))
    }
}

/// 2×2 facts: Address, Driving hours, Closes above, Nearest cam. Cells with
/// no data show a dash — nulls are expected until the metadata is curated.
struct FactsGrid: View {
    let ramp: Ramp
    let nearestCam: String?
    /// 2×2 on iPhone; 4 across in the iPad sheet.
    var columns: Int = 2
    @Environment(\.ground) private var ground

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
            if columns == 4 {
                GridRow {
                    fact("Address", ramp.address)
                    fact("Driving hours", ramp.drivingHours)
                    fact("Closes above", ramp.closureHeightFt.map { String(format: "%.1f ft tide", $0) })
                    fact("Nearest cam", nearestCam)
                }
            } else {
                GridRow {
                    fact("Address", ramp.address)
                    fact("Driving hours", ramp.drivingHours)
                }
                GridRow {
                    fact("Closes above", ramp.closureHeightFt.map { String(format: "%.1f ft tide", $0) })
                    fact("Nearest cam", nearestCam)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String?) -> some View {
        let t = ground.tokens
        return VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(t.rule).frame(height: 2)
            Text(label.uppercased())
                .font(.archivo(10, weight: .bold))
                .tracking(10 * ArchivoTracking.kicker)
                .foregroundStyle(t.ink2)
            Text(value ?? "—")
                .font(.archivo(15, weight: .extraBold))
                .foregroundStyle(t.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

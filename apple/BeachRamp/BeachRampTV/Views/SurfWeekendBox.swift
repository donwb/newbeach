import SwiftUI
import BeachStatus

/// The right-hand box: the surf read on top, the weekend underneath. Read
/// only in v1 — the surf ‹ › time-paging ships when the server has future
/// surf windows, and the box layout is built to take the chevrons without
/// moving anything else.
struct SurfWeekendBox: View {
    let surf: TVSurfBoxModel
    let weekend: [TVWeekendSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Surf").tvLabel()
                    Text(surf.windowLabel).tvLabel(24, color: TVInk.type)
                }
                Text(surf.headline)
                    .tv(42, .extraBold, tracking: -0.025)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(TVInk.type.opacity(surf.hasRead ? 1.0 : 0.72))
                Text(surf.detail)
                    .tv(26)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(TVInk.typeMuted)
            }

            Spacer(minLength: 12)

            if !weekend.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This weekend").tvLabel()
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(weekend.prefix(2).enumerated()), id: \.element.id) { index, slot in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(slot.dayName)
                                    .tv(28, .extraBold)
                                    .foregroundStyle(TVInk.type)
                                Text(slot.headline)
                                    .tv(30, .semiBold)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(TVInk.type)
                                Text(slot.metrics)
                                    .tv(24)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(TVInk.typeDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, index > 0 ? 40 : 0)
                            .overlay(alignment: .leading) {
                                if index > 0 {
                                    Rectangle().fill(TVInk.type.opacity(0.2)).frame(width: 1)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(TVInk.rule).frame(height: 2)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Surf + weekend", traits: .fixedLayout(width: 852, height: 420)) {
    SurfWeekendBox(
        surf: TVSurfBoxModel(
            windowLabel: "Now",
            headline: "Pretty much flat out there",
            detail: "Knee-high · 6s · rip risk low · buoy read 40 min ago",
            hasRead: true
        ),
        weekend: [
            TVWeekendSlot(id: "2026-08-22", dayName: "Saturday",
                          headline: "Best 9am–1pm", metrics: "93° · mid-day close potential"),
            TVWeekendSlot(id: "2026-08-23", dayName: "Sunday",
                          headline: "Wide open all day", metrics: "91° · clear all day"),
        ]
    )
    .padding(40)
    .background(TVSkyGround.noon.gradient)
}
#endif

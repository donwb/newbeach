import SwiftUI
import BeachStatus

/// The row that opens the landscape cam view. A 1280×270 panorama does not
/// fit a portrait column — the cam lives in its own landscape screen. This
/// row should simply not appear when the camera roster is empty. It says
/// up front whether the cam is live video or the still fallback.
struct CamRowView: View {
    let cameraName: String
    var mode: CamMode = .live
    let action: () -> Void
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    CamModeBadge(mode: mode, tint: t.ink2)
                    Text("\(mode == .live ? "Live cam" : "Beach cam") · \(cameraName)")
                        .font(.archivo(17, weight: .extraBold))
                        .foregroundStyle(t.ink)
                    Text(subtitle)
                        .font(.archivo(11))
                        .foregroundStyle(t.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.accent)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressTintButtonStyle())
        .accessibilityLabel("\(accessibilityMode), \(cameraName). Opens full screen in landscape.")
    }

    private var subtitle: String {
        switch mode {
        case .live: "Turn the phone sideways to watch"
        case .still: "A still photo for now, refreshed every few minutes"
        case .offline: "Offline right now"
        }
    }

    private var accessibilityMode: String {
        switch mode {
        case .live: "Live cam"
        case .still: "Beach cam still photo"
        case .offline: "Beach cam, offline"
        }
    }
}

/// The board's footer: sources and the feed timestamp.
struct BoardFooterView: View {
    let updatedAt: Date?
    @Environment(\.ground) private var ground

    var body: some View {
        let t = ground.tokens
        VStack(alignment: .leading, spacing: 2) {
            Text("NOAA · Volusia County Beach Safety")
                .font(.archivo(11))
                .foregroundStyle(t.ink2)
            if let updatedAt {
                Text("Updated \(SinceFormatter.clock(updatedAt))")
                    .font(.archivo(11))
                    .monospacedDigit()
                    .foregroundStyle(t.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Cam row · live / still / offline") {
    VStack(spacing: 0) {
        CamRowView(cameraName: "New Smyrna Beach", mode: .live) {}
        CamRowView(cameraName: "New Smyrna Beach", mode: .still) {}
        CamRowView(cameraName: "Ormond-By-The-Sea", mode: .offline) {}
    }
    .padding(.horizontal, 18)
}
#endif

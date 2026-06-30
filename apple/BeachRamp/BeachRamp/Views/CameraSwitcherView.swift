import SwiftUI
import BeachStatus

/// Touch camera switcher for the iPad layout — a horizontally scrollable row of
/// tappable chips above the beach-cam banner. Tapping switches the active
/// stream. The selected chip is filled with the ocean accent; cameras the cron
/// hasn't resolved yet (or that are offline) are dimmed with a slashed icon.
struct CameraSwitcherView: View {
    let cameras: [Camera]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(cameras) { cam in
                    let isSelected = cam.id == selectedID
                    let isLive = cam.url != nil
                    Button {
                        onSelect(cam.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isLive ? "video.fill" : "video.slash.fill")
                                .font(.caption)
                            Text(cam.name)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : AppColors.primaryText)
                        .opacity(isLive ? 1 : 0.5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AppColors.oceanAccent : AppColors.nestedCardBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            // Inset so chip shadows/fills aren't clipped by the scroll edges.
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    CameraSwitcherView(
        cameras: [
            Camera(id: "nsb", name: "New Smyrna Beach", location: "New Smyrna Beach",
                   streamURL: "https://example.com/a.m3u8"),
            Camera(id: "ponce-inlet", name: "Ponce Inlet", location: "Ponce Inlet",
                   streamURL: "https://example.com/b.m3u8"),
            Camera(id: "dunlawton", name: "Dunlawton", location: "Daytona Beach Shores",
                   streamURL: ""),
            Camera(id: "ormond-beach", name: "Ormond Beach", location: "Ormond Beach",
                   streamURL: "https://example.com/c.m3u8")
        ],
        selectedID: "nsb",
        onSelect: { _ in }
    )
    .padding()
}

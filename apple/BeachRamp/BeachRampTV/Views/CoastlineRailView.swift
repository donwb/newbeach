import SwiftUI
import BeachStatus

// MARK: - Coastline Rail (camera switcher)

/// Camera switcher as a row of flat rules, ordered north (left) to south
/// (right). The active camera's name is bold over a 4pt solid white rule;
/// inactive pins are quiet 2pt rules. Moving focus channel-flips the stream;
/// clicking selects too. A Recent changes button sits at the right edge
/// (the Menu press remains a shortcut to the same overlay).
struct CoastlineRail: View {
    let cameras: [Camera]
    let selectedID: String?
    @FocusState.Binding var focusedCamera: String?
    /// Owned by ContentView so closing the Recent-changes overlay can hand
    /// focus back to the button that opened it.
    @FocusState.Binding var recentChangesFocused: Bool
    let onSelect: (String) -> Void
    let onRecentChanges: () -> Void

    /// North→south ordering along the Volusia coast, keyed by camera id.
    /// Matches the geographic positions the old pin rail used.
    private static let coastPosition: [String: Double] = [
        "ormond-by-the-sea": 0.06,
        "ormond-beach":      0.28,
        "dunlawton":         0.50,
        "ponce-inlet":       0.72,
        "nsb":               0.94,
    ]

    /// Cameras ordered north→south. Unknown ids keep roster order, which runs
    /// south→north, so it is reversed to match.
    private var orderedCameras: [Camera] {
        if cameras.allSatisfy({ Self.coastPosition[$0.id] != nil }) {
            return cameras.sorted {
                (Self.coastPosition[$0.id] ?? 1) < (Self.coastPosition[$1.id] ?? 1)
            }
        }
        return cameras.reversed()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(orderedCameras) { camera in
                    Button {
                        onSelect(camera.id)
                    } label: {
                        CoastPin(
                            name: camera.name,
                            isSelected: camera.id == selectedID,
                            isFocused: camera.id == focusedCamera,
                            isOffline: camera.url == nil
                        )
                    }
                    .buttonStyle(CoastPinButtonStyle())
                    .focused($focusedCamera, equals: camera.id)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 1420, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                onRecentChanges()
            } label: {
                Label("Recent changes", systemImage: "line.3.horizontal")
                    .font(.system(size: 22))
                    .opacity(recentChangesFocused ? 1.0 : 0.6)
            }
            .buttonStyle(FlatFocusButtonStyle(
                isFocused: recentChangesFocused,
                horizontalPadding: 16,
                verticalPadding: 8,
                idleFill: 0,
                idleBorder: 0
            ))
            .focused($recentChangesFocused)
        }
        .focusSection()
        .animation(.easeOut(duration: 0.15), value: focusedCamera)
        .animation(.easeOut(duration: 0.15), value: selectedID)
    }
}

/// Button style for coast pins that contributes **no focus chrome of its own** —
/// the pin draws all of its own focus/selection state. Necessary because on
/// tvOS `.buttonStyle(.plain)` still lets the system paint its frosted focus
/// "bulge"; supplying a custom ButtonStyle fully replaces it.
struct CoastPinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// One camera pin: name over a full-width rule. Active = bold name, 4pt solid
/// white rule; inactive = 55% name, 2pt faint rule. Focus (before selection
/// lands) brightens the name so the remote position is visible.
private struct CoastPin: View {
    let name: String
    let isSelected: Bool
    let isFocused: Bool
    let isOffline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 22, weight: isSelected ? .bold : .regular))
                .foregroundStyle(.white.opacity(nameOpacity))
                .lineLimit(1)
            Rectangle()
                .fill(isSelected ? Color.white : Color.white.opacity(0.28))
                .frame(height: isSelected ? 4 : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isOffline ? 0.5 : 1.0)
    }

    private var nameOpacity: Double {
        if isSelected { return 1.0 }
        if isFocused { return 0.85 }
        return 0.55
    }
}

#if DEBUG
#Preview {
    @Previewable @FocusState var focused: String?
    @Previewable @FocusState var recentFocused: Bool
    ZStack {
        Color(red: 0.05, green: 0.5, blue: 0.66).ignoresSafeArea()
        VStack {
            Spacer()
            CoastlineRail(
                cameras: PreviewFixtures.cameras,
                selectedID: "nsb",
                focusedCamera: $focused,
                recentChangesFocused: $recentFocused,
                onSelect: { _ in },
                onRecentChanges: {}
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 52)
        }
    }
}
#endif

import SwiftUI
import BeachStatus

// MARK: - Coastline Rail (camera switcher)

/// Camera switcher styled as a stretch of coastline: each camera is a pin placed
/// at its geographic position (north on the left, south on the right). The live
/// camera keeps a persistent ring + "Live" tag; the focused pin (wherever the
/// remote sits) pops a name pill above it. Moving focus channel-flips the stream;
/// clicking selects too.
struct CoastlineRail: View {
    let cameras: [Camera]
    let selectedID: String?
    @FocusState.Binding var focusedCamera: String?
    let onSelect: (String) -> Void

    /// Normalized coast position (0 = north / left, 1 = south / right), keyed by
    /// camera id. Hand-tuned from the real Volusia latitudes for legible spacing.
    private static let coastPosition: [String: Double] = [
        "ormond-by-the-sea": 0.06,
        "ormond-beach":      0.28,
        "dunlawton":         0.50,
        "ponce-inlet":       0.72,
        "nsb":               0.94,
    ]

    /// True when every camera has a mapped position; otherwise we even-space all
    /// of them (by roster order, which runs south→north) so a future or unknown
    /// camera still lands somewhere sensible and consistent.
    private var allMapped: Bool {
        cameras.allSatisfy { Self.coastPosition[$0.id] != nil }
    }

    private func position(for camera: Camera, index: Int) -> Double {
        if allMapped, let mapped = Self.coastPosition[camera.id] { return mapped }
        guard cameras.count > 1 else { return 0.5 }
        // Roster is south→north; place north (last) on the left to match the map.
        return 0.94 - 0.88 * Double(index) / Double(cameras.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let rowCenterY: CGFloat = 41
            ZStack(alignment: .topLeading) {
                // North / south anchors
                Text("N")
                    .coastAnchor()
                    .position(x: 12, y: rowCenterY)
                Text("S")
                    .coastAnchor()
                    .position(x: w - 12, y: rowCenterY)

                // The coast line
                Capsule()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.32)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: w - 40, height: 2)
                    .position(x: w / 2, y: rowCenterY)

                // Pins
                ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
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
                    .position(x: clamp(CGFloat(position(for: camera, index: index)) * w, 80, w - 80), y: rowCenterY)
                }
            }
        }
        .frame(height: 82)
        .focusSection()
        .animation(.easeOut(duration: 0.15), value: focusedCamera)
    }

    private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(lo, value), max(lo, hi))
    }
}

/// Button style for coast pins that contributes **no focus chrome of its own** —
/// the pin draws all of its own focus/selection state (halo, name pill, ring).
/// Necessary because on tvOS `.buttonStyle(.plain)` still lets the system paint
/// its frosted focus "bulge"; supplying a custom ButtonStyle fully replaces it.
struct CoastPinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A single coastline camera pin: a dot on the coast line with its name below,
/// a name pill above when focused, and a persistent ring + "Live" tag when it is
/// the active stream.
private struct CoastPin: View {
    let name: String
    let isSelected: Bool
    let isFocused: Bool
    let isOffline: Bool

    private static let live = Color(red: 0.32, green: 0.68, blue: 1.0)
    private static let ring = Color(red: 0.12, green: 0.48, blue: 0.88)
    private static let pillText = Color(red: 0.05, green: 0.13, blue: 0.22)

    var body: some View {
        ZStack {
            if isFocused {
                Text(name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Self.pillText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white))
                    .fixedSize()
                    .offset(y: -30)
            }

            dot

            if !isFocused {
                Text(name)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isOffline ? 0.4 : (isSelected ? 1.0 : 0.7)))
                    .fixedSize()
                    .offset(y: 26)
            }

            if isSelected && !isOffline {
                Text("Live")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.live)
                    .offset(y: isFocused ? 24 : 44)
            }
        }
        .frame(width: 160, height: 82)
    }

    @ViewBuilder private var dot: some View {
        if isOffline {
            Circle()
                .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 14, height: 14)
        } else if isFocused {
            ZStack {
                Circle().fill(.white.opacity(0.28)).frame(width: 30, height: 30)
                Circle().fill(.white).frame(width: 16, height: 16)
            }
        } else if isSelected {
            ZStack {
                Circle().fill(Self.ring.opacity(0.35)).frame(width: 26, height: 26)
                Circle().fill(.white).frame(width: 15, height: 15)
                Circle().stroke(Self.ring, lineWidth: 3).frame(width: 15, height: 15)
            }
        } else {
            Circle().fill(.white.opacity(0.55)).frame(width: 11, height: 11)
        }
    }
}

private extension Text {
    /// Styling for the small N / S coastline anchors.
    func coastAnchor() -> some View {
        self.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
    }
}

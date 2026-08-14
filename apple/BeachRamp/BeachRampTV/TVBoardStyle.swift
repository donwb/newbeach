import SwiftUI

// MARK: - Flat Focus Button Style

/// A tvOS button style that fully replaces the system's frost-and-lift focus
/// treatment with a flat chip: a translucent fill and a hairline border that
/// brighten on focus, plus a tiny press dip. No scaling on focus, so focused
/// chips stay put instead of ballooning over their neighbors.
struct FlatFocusButtonStyle: ButtonStyle {
    var isFocused: Bool
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(isFocused ? 0.26 : (isSelected ? 0.14 : 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        .white.opacity(isFocused ? 1.0 : (isSelected ? 0.6 : 0)),
                        lineWidth: isFocused ? 2.5 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Glass Card Styling

/// Frosted-glass card surface — translucent material with a hairline highlight,
/// so cards read as floating over the sky rather than flat fills.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

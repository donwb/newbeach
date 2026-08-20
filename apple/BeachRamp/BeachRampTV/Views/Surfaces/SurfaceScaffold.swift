import SwiftUI

/// Shared chrome for the two pull surfaces. A surface replaces the ledger
/// and the cam strip — 630pt on an opaque ink field — and never the picture:
/// the header and the beach hold still while the bottom cross-fades.
///
/// The scaffold owns focus while open via a hidden focusable (the surfaces
/// themselves are read-only), so Back has a home to fire from; the header's
/// outlook button leaves the focus graph while a surface is up.
struct SurfaceScaffold<Content: View>: View {
    /// Accessibility identifier for the whole surface ("surface.outlook") —
    /// exposed as a container so UI tests can see it.
    let identifier: String
    let focus: FocusState<RootFocus?>.Binding
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            TVInk.ground
            content
            // Hidden focus owner — keeps the engine anchored down here.
            Color.clear
                .frame(width: 1, height: 1)
                .focusable()
                .focused(focus, equals: .surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
        .onExitCommand(perform: onClose)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The "Back returns the ledger" hint every surface carries at its top right.
struct SurfaceBackHint: View {
    var body: some View {
        Text("Back returns the ledger")
            .tv(24)
            .foregroundStyle(TVInk.inactive)
    }
}

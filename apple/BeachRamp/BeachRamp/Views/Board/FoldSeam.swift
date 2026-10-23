import SwiftUI

/// The iPhone Duo's hinge, where it runs top-to-bottom through the board —
/// the open "book" pose, 951×669pt with the hinge at the screen's centerline.
/// The iPad board's landscape arrangement splits there (headline | stats,
/// ramps | conditions rail) so nothing straddles the fold.
///
/// The seam is the screen midline by geometry (the hinge is the device's
/// centerline by construction); the `.division` reserved region, which the
/// 27.1 release reports (beta 1 never did), is preferred when present.
/// The trailing 84pt of the book pose belongs to the system's status strip,
/// so the pages are asymmetric — centering on the *safe area* would put the
/// split 42pt off the hinge.
///
/// 27.1 SDK only (SwiftUICore 8.0.85); on an older SDK the app runs in the
/// Duo's compatibility mode and there is no seam to align to.
enum FoldSeam {
    /// The seam's x in `proxy`'s own coordinates, or nil when there is no
    /// vertical hinge through this view (every other device and pose).
    static func verticalSeam(in proxy: GeometryProxy, hingeOpen: Bool) -> CGFloat? {
        #if canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // Lying flat the division reports `isActive == false`, but its
            // frame still marks the hinge (x 455–495 of 951 on the sim).
            if let region = proxy.reservedRegions(kind: .division, options: [.includeInactive])
                .first(where: { $0.frame.height > $0.frame.width }) {
                return region.frame.midX
            }
            guard hingeOpen, proxy.size.width > proxy.size.height else { return nil }
            let insets = proxy.safeAreaInsets
            let screenWidth = proxy.size.width + insets.leading + insets.trailing
            return screenWidth / 2 - insets.leading
        }
        #endif
        return nil
    }
}

extension View {
    /// Tracks whether the device has a hinge that is open (fully or
    /// partially). False on every device without one, and on older SDKs.
    func trackingHinge(_ isOpen: Binding<Bool>) -> some View {
        modifier(HingeTracker(isOpen: isOpen))
    }
}

private struct HingeTracker: ViewModifier {
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        #if canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // The callback fires continuously mid-fold with an unchanged
            // status; only write when the answer actually changes.
            content.onHingeChange { _, new in
                let open = new.hinge.map { $0.status != .closed } ?? false
                if open != isOpen { isOpen = open }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

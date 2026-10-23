#if DEBUG
import SwiftUI
import os

/// QA hook: `--layout-probe` logs the geometry the board is actually handed
/// on every change — size classes, window size, safe-area insets, and (27.1
/// SDK) the fold's reserved regions + hinge status. Built for the iPhone Duo
/// pose walk: launch with `simctl launch --console`, flip the poses in
/// Xcode's Device Hub, read the `[layout-probe]` lines.
///
/// Ported from Refrain's probe. The fold APIs are gated on the SwiftUICore
/// version, not `compiler(>=)`: 27.0 and 27.1 both carry Swift 6.4, and
/// only 27.1 (SwiftUICore 8.0.85) has `ReservedRegion` / `onHingeChange`.
struct LayoutProbe: ViewModifier {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("--layout-probe")
    private static let log = Logger(subsystem: "com.donwb.BeachRampTV", category: "layout")

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let line = Self.describe(proxy, h: hSize, v: vSize)
                    Color.clear
                        .onAppear { Self.emit(line) }
                        .onChange(of: line) { _, new in Self.emit(new) }
                }
            }
            .modifier(HingeLogger())
    }

    fileprivate static func emit(_ line: String) {
        log.notice("\(line, privacy: .public)")
        print("[layout-probe] \(line)")
    }

    private static func describe(
        _ proxy: GeometryProxy, h: UserInterfaceSizeClass?, v: UserInterfaceSizeClass?
    ) -> String {
        func name(_ c: UserInterfaceSizeClass?) -> String {
            switch c {
            case .compact: "compact"
            case .regular: "regular"
            default: "nil"
            }
        }
        let s = proxy.size
        let i = proxy.safeAreaInsets
        let g = proxy.frame(in: .global)
        var parts = [
            "h=\(name(h)) v=\(name(v))",
            "size=\(Int(s.width))x\(Int(s.height))",
            "global=\(Int(g.minX)),\(Int(g.minY))",
            "safe(t:\(Int(i.top)) l:\(Int(i.leading)) b:\(Int(i.bottom)) tr:\(Int(i.trailing)))",
        ]
        #if canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            for (label, kind) in [("division", ReservedRegion.Kind.division),
                                  ("occlusion", ReservedRegion.Kind.occlusion)] {
                let regions = proxy.reservedRegions(kind: kind, options: [.includeInactive])
                let text = regions.map { r in
                    let f = r.frame, m = r.margins
                    return "[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))"
                        + " active=\(r.isActive)"
                        + " margins(t:\(Int(m.top)) l:\(Int(m.leading)) b:\(Int(m.bottom)) tr:\(Int(m.trailing)))]"
                }.joined(separator: " ")
                parts.append("\(label)=\(text.isEmpty ? "none" : text)")
            }
        }
        #endif
        return parts.joined(separator: " · ")
    }
}

private struct HingeLogger: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onHingeChange { old, new in
                LayoutProbe.emit("hinge \(String(describing: old.hinge?.status)) → \(String(describing: new.hinge?.status))")
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    @ViewBuilder
    func layoutProbeIfRequested() -> some View {
        if LayoutProbe.isRequested { modifier(LayoutProbe()) } else { self }
    }
}
#endif

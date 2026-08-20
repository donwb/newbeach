import SwiftUI
import BeachStatus

// MARK: - Video-first design tokens
// From the "tvOS Video First — Final" handoff (2026-08-20). Radius is zero
// everywhere; structure is carried by 2pt rules, not rounding or materials.
// Two rules carry the palette: red means closed and nothing else, and every
// interactive accent (focus, active cam, scroll thumb, the outlook button)
// is dry sand — which holds on every ground because the type never sits on
// the bare sky: the ground is the shared full-brightness SkyPalette (Don's
// call, 2026-08-20 — the dark TVSkyGround re-voicing was reverted), and the
// header and ledger regions lay a translucent ink veil (TVSky) over it so
// the sky's sixteen phases glow through while type keeps its contrast.

enum TVInk {
    /// Base frame under the day-part gradient.
    static let ground = Color(boardHex: 0x100F0E)
    /// All primary type; "Open" status.
    static let type = Color(boardHex: 0xF3F2F2)
    /// CLOSED ONLY: closed status, closed timeline segments, the verdict bar
    /// when a ramp is shut, the worst closure risk in the outlook.
    static let closed = Color(boardHex: 0xEC3013)
    /// Focus, scroll thumb, active-cam underline, outlook button, all-open
    /// verdict bar, today marker, detail kickers.
    static let sand = Color(boardHex: 0xF0DDB4)

    static let typeMuted = type.opacity(0.72)
    static let typeDim = type.opacity(0.62)
    static let label = type.opacity(0.55)
    static let inactive = type.opacity(0.50)
    /// 2px structural rules.
    static let rule = type.opacity(0.30)
    /// 1px row rules.
    static let ruleHair = type.opacity(0.18)
    /// Scroll track, timeline track.
    static let track = type.opacity(0.16)
    /// The verdict bar overnight — neither alarm nor all-clear.
    static let barMuted = type.opacity(0.40)
    /// Ink on a sand fill (focused outlook button).
    static let onSand = Color(boardHex: 0x100F0E)
}

/// The sun-following ground and its legibility veils. The sky itself is the
/// shared sixteen-phase SkyPalette — bright midday blues, amber golden hours
/// — rendered at full strength; the veils are what let #F3F2F2 type and sand
/// accents sit on it. The ledger's veil runs heavier toward the screen
/// bottom, countering the sky gradient's pale bottom stops; the picture band
/// is never veiled.
enum TVSky {
    /// Veil ink — the v3 board's panel-field hue.
    static let veilInk = Color(boardHex: 0x041A28)
    static let headerVeilOpacity = 0.32
    static let ledgerVeilTopOpacity = 0.42
    static let ledgerVeilBottomOpacity = 0.62

    static var headerVeil: some View {
        veilInk.opacity(headerVeilOpacity)
    }

    static var ledgerVeil: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: veilInk.opacity(ledgerVeilTopOpacity), location: 0),
                .init(color: veilInk.opacity(ledgerVeilBottomOpacity), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // Preview grounds — the shared palette's noon and deep night.
    static var previewNoon: LinearGradient {
        SkyPalette.forSun(altitude: 48, isRising: true).gradient
    }
    static var previewNight: LinearGradient {
        SkyPalette.forSun(altitude: -30, isRising: false).gradient
    }
}

enum TVMetrics {
    static let header: CGFloat = 110
    static let picture: CGFloat = 340
    static let camStrip: CGFloat = 56
    static let sidePad: CGFloat = 64
    /// Ledger height = 1080 − header − picture − camStrip; the pull surfaces
    /// take ledger + camStrip.
    static let ledger: CGFloat = 574
    static let surface: CGFloat = 630
    /// Pull-surface cross-fade.
    static let surfaceTransition: TimeInterval = 0.24
}

extension Color {
    init(boardHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Type helpers
// All type in the target goes through these — Archivo via the shared
// package's registered faces, no .system fonts anywhere.

extension Text {
    /// Archivo at `size`/`weight` with em-tracking (e.g. -0.025).
    func tv(_ size: CGFloat, _ weight: BeachFont.Weight = .regular, tracking em: CGFloat = 0) -> Text {
        self.font(.archivo(size, weight: weight)).tracking(size * em)
    }

    /// The 24px label floor: semibold uppercase, 0.1em tracking.
    func tvLabel(_ size: CGFloat = 24, color: Color = TVInk.label) -> some View {
        self.tv(size, .semiBold, tracking: 0.1)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

// MARK: - Status wording

/// Compact display words for the county's raw status strings, used by the
/// ledger's Now column and the detail surface's event log. Factual states,
/// not predictions — safe to word client-side.
func tvStatusWord(_ raw: String) -> String {
    switch raw.uppercased().trimmingCharacters(in: .whitespaces) {
    case "OPEN": "Open"
    case "CLOSED": "Closed"
    case "CLOSED FOR HIGH TIDE": "Closed — high tide"
    case "CLOSED - CLEARED FOR TURTLES": "Closed — turtles"
    case "CLOSED - AT CAPACITY": "Closed — at capacity"
    case "4X4 ONLY": "4x4 only"
    case "OPEN - ENTRANCE ONLY": "Entrance only"
    case "CLOSING IN PROGRESS": "Closing"
    default: raw.titleCased
    }
}

// MARK: - Button styles

/// Contributes no focus chrome of its own — the label draws all focus and
/// selection state. `.plain` still paints the system's frosted bulge on
/// tvOS; a custom ButtonStyle fully replaces it.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

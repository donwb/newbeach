import CoreText
import Foundation
import SwiftUI

/// Archivo, bundled as package resources and registered at runtime so every
/// target (app, widget extension, watch) gets the family without per-target
/// Info.plist entries. Call `BeachFont.registerFonts()` once from each
/// process entry point before any text renders.
public enum BeachFont {
    public enum Weight: String, CaseIterable, Sendable {
        case regular = "Archivo-Regular"      // 400
        case semiBold = "Archivo-SemiBold"    // 600
        case bold = "Archivo-Bold"            // 700
        case extraBold = "Archivo-ExtraBold"  // 800

        var fileName: String { rawValue }
        public var postScriptName: String { rawValue }
    }

    private static let registration: Void = {
        for weight in Weight.allCases {
            guard let url = Bundle.module.url(
                forResource: weight.fileName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                assertionFailure("Missing bundled font \(weight.fileName).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is fine (kCTFontManagerErrorAlreadyRegistered
                // or a duplicate PostScript name); anything else is a packaging bug.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) }
                if code != CTFontManagerError.alreadyRegistered.rawValue,
                   code != CTFontManagerError.duplicatedName.rawValue {
                    assertionFailure("Failed to register \(weight.fileName): code \(code.map(String.init) ?? "unknown")")
                }
            }
        }
    }()

    public static func registerFonts() {
        _ = registration
    }
}

/// Letter-spacing values from the design handoff, in ems.
/// Use with `.tracking(size * ArchivoTracking.…)`.
public enum ArchivoTracking {
    /// Verdict headline: −0.03em
    public static let headline: CGFloat = -0.03
    /// Ramp names: −0.015em
    public static let rampName: CGFloat = -0.015
    /// Kickers / labels: 0.09em uppercase
    public static let kicker: CGFloat = 0.09
}

public extension Font {
    static func archivo(_ size: CGFloat, weight: BeachFont.Weight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}

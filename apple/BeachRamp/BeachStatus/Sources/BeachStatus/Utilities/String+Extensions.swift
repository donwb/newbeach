import Foundation

extension String {
    /// Converts an UPPERCASE or lowercase string to Title Case.
    ///
    /// Example: "NEW SMYRNA BEACH" → "New Smyrna Beach"
    public var titleCased: String {
        lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

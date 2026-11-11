import Foundation

/// A stable, validated identifier for a Google Cloud resource.
///
/// Resources are referenced internally by these identifiers rather than
/// by display names (which are mutable and may be attacker-controlled
/// VM metadata). Values are validated against a conservative character
/// set so they can never carry shell metacharacters into process
/// invocation (see THREAT_MODEL threats 2 and 5).
public struct ResourceIdentifier: Hashable, Sendable, CustomStringConvertible {

    public enum ValidationError: Error, Equatable, Sendable {
        case empty
        case tooLong(Int)
        case illegalCharacters
    }

    /// Google Cloud project IDs, zone names, and instance names use a
    /// restricted set: lowercase letters, digits, hyphens, and for some
    /// fully-qualified IDs, dots, slashes, and colons. We allow that
    /// union but explicitly forbid whitespace and shell metacharacters.
    private static let allowed = CharacterSet(
        charactersIn:
            "abcdefghijklmnopqrstuvwxyz" +
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            "0123456789" +
            "-._/:"
    )

    private static let maxLength = 512

    public let rawValue: String

    public init(validating raw: String) throws {
        guard !raw.isEmpty else { throw ValidationError.empty }
        guard raw.count <= Self.maxLength else {
            throw ValidationError.tooLong(raw.count)
        }
        guard raw.unicodeScalars.allSatisfy(Self.allowed.contains) else {
            throw ValidationError.illegalCharacters
        }
        self.rawValue = raw
    }

    public var description: String { rawValue }
}

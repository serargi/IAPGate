import Foundation

/// User-facing theme preference.
public enum AppearancePreference: String, Sendable, CaseIterable, Codable {
    case system
    case light
    case dark
}

/// Interface language. The app ships English and Spanish from v1.
public enum LanguagePreference: String, Sendable, CaseIterable, Codable {
    case system
    case english = "en"
    case spanish = "es"
}

/// Preferred default connection type when a VM supports more than one.
public enum ConnectionTypePreference: String, Sendable, CaseIterable, Codable {
    case ssh
    case rdp
}

/// Non-secret user preferences.
///
/// This type is intentionally free of any credential or token field.
/// Secrets live only in the Keychain via `SecureCredentialStore`
/// (security rule: never persist tokens in UserDefaults). Keeping the
/// two stores as distinct types makes that separation structural
/// rather than a convention someone can forget.
public struct Preferences: Sendable, Equatable, Codable {
    public var appearance: AppearancePreference
    public var language: LanguagePreference
    public var defaultConnectionType: ConnectionTypePreference

    /// Default SSH username used when a VM does not specify one.
    /// Non-secret; the username is not a credential.
    public var defaultSSHUsername: String?

    /// Bundle identifier or absolute path of the preferred external RDP
    /// client. Non-secret.
    public var preferredRDPClient: String?

    /// How many recent connections to retain. Enforces a bounded
    /// history (privacy/retention rule).
    public var recentConnectionsLimit: Int

    public static let `default` = Preferences(
        appearance: .system,
        language: .system,
        defaultConnectionType: .ssh,
        defaultSSHUsername: nil,
        preferredRDPClient: nil,
        recentConnectionsLimit: 20
    )

    public init(
        appearance: AppearancePreference,
        language: LanguagePreference,
        defaultConnectionType: ConnectionTypePreference,
        defaultSSHUsername: String?,
        preferredRDPClient: String?,
        recentConnectionsLimit: Int
    ) {
        self.appearance = appearance
        self.language = language
        self.defaultConnectionType = defaultConnectionType
        self.defaultSSHUsername = defaultSSHUsername
        self.preferredRDPClient = preferredRDPClient
        // Clamp to a sane, bounded range so a corrupted value can never
        // produce an unbounded history.
        self.recentConnectionsLimit = min(max(recentConnectionsLimit, 0), 100)
    }
}

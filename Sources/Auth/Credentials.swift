import Foundation

/// A signed-in account. With gcloud-based auth the identity is the
/// account email (which gcloud reports and uses for its session).
public struct Account: Equatable, Sendable, Codable, Identifiable {
    /// Stable identifier. For gcloud auth this is the account email.
    public let id: String
    public let email: String?
    public let displayName: String?

    public init(id: String, email: String?, displayName: String?) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

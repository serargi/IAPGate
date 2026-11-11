import Foundation
import CloudGateCore

/// Supplies a valid access token for Google API calls.
///
/// Abstracted so discovery/transport layers depend on this small
/// surface rather than a concrete auth implementation, and so it can be
/// mocked in tests. The production implementation is
/// `GcloudAccessTokenProvider`, which obtains tokens from the gcloud
/// CLI (which owns the session and its refresh).
public protocol AccessTokenProviding: Sendable {
    /// Returns a currently-valid access token for the given account.
    func validAccessToken(for accountID: String) async -> Result<String, CloudGateError>
}

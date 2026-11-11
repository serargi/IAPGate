import Foundation
import CloudGateCore

/// The authentication operations the session gate depends on.
///
/// Abstracted so the gate logic is testable without a browser or
/// network. The production implementation (browser + token exchange +
/// Keychain) conforms to this; tests use a scripted double.
public protocol AuthenticationProvider: Sendable {
    /// Returns the account for an already-stored, still-valid (or
    /// refreshable) session, or nil if there is none. Called at launch.
    func restoreSession() async -> Result<Account?, CloudGateError>

    /// Runs the interactive sign-in flow (opens the browser, completes
    /// the PKCE exchange, stores tokens) and returns the account.
    func signIn() async -> Result<Account, CloudGateError>

    /// Signs out: deletes stored credentials and best-effort revokes.
    func signOut(account: Account) async
}

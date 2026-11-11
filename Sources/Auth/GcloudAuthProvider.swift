import Foundation
import CloudGateCore

/// Authentication backed by the Google Cloud CLI (`gcloud`).
///
/// Instead of running our own OAuth client (which would require every
/// user to register a client ID/secret), we reuse gcloud's own login:
/// - sign in runs `gcloud auth login` (opens the browser),
/// - the session is stored and refreshed by gcloud itself,
/// - API calls use `gcloud auth print-access-token`.
///
/// This removes the OAuth client, the client secret, the provisioning
/// CLI, and credential storage in our Keychain entirely. gcloud is
/// already required for IAP connections, so this adds no new dependency.
public final class GcloudAuthProvider: AuthenticationProvider, @unchecked Sendable {

    /// Abstraction over running gcloud, so this is testable.
    public protocol Runner: Sendable {
        /// Runs gcloud with `arguments`, returns (stdout, exitCode).
        /// `interactive` lets the process use the terminal/browser
        /// (for `auth login`).
        @discardableResult
        func run(_ arguments: [String], interactive: Bool) async -> (output: String, exitCode: Int32)
    }

    private let runner: Runner

    public init(runner: Runner) {
        self.runner = runner
    }

    // MARK: - AuthenticationProvider

    public func restoreSession() async -> Result<Account?, CloudGateError> {
        // Who is the active gcloud account, if any?
        let (account, code) = await runner.run(
            ["config", "get-value", "account", "--quiet"], interactive: false)
        let email = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !email.isEmpty, email != "(unset)" else {
            return .success(nil)
        }
        // Confirm the session can actually mint a token (not expired and
        // not revoked). If it can't, treat as signed-out.
        let (_, tokenCode) = await runner.run(
            ["auth", "print-access-token", "--quiet"], interactive: false)
        guard tokenCode == 0 else { return .success(nil) }

        return .success(Account(id: email, email: email, displayName: email))
    }

    public func signIn() async -> Result<Account, CloudGateError> {
        // Opens the browser; gcloud stores and refreshes the session.
        let (_, code) = await runner.run(["auth", "login"], interactive: true)
        guard code == 0 else {
            return .failure(.make(
                .authenticationFailed,
                userMessage: "Google sign-in did not complete.",
                technicalDetail: "gcloud auth login exit \(code)"))
        }
        switch await restoreSession() {
        case .success(let account?):
            return .success(account)
        case .success(nil):
            return .failure(.make(
                .authenticationFailed,
                userMessage: "Sign-in did not become active. Please try again."))
        case .failure(let error):
            return .failure(error)
        }
    }

    public func signOut(account: Account) async {
        // Revoke the gcloud credential for this account.
        _ = await runner.run(
            ["auth", "revoke", account.email ?? account.id, "--quiet"],
            interactive: false)
    }
}

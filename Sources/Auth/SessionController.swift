import Foundation
import Observation
import CloudGateCore

/// Drives the authentication gate.
///
/// On launch the UI creates one of these, reads `state`, and renders:
/// login when `.unauthenticated`, the app when `.authenticated`, a
/// brief spinner when `.checking`. The controller owns all transitions.
///
/// `@Observable` so SwiftUI re-renders when `state` changes.
/// `@MainActor` because `state` is UI-observable state; the actual
/// network/browser work happens inside the injected
/// `AuthenticationProvider` off the main actor.
@MainActor
@Observable
public final class SessionController {

    public private(set) var state: SessionState = .checking {
        didSet { onStateChange?(state) }
    }

    /// Optional observer hook, retained for non-SwiftUI tests.
    @ObservationIgnored
    public var onStateChange: (@MainActor (SessionState) -> Void)?

    @ObservationIgnored
    private let provider: AuthenticationProvider

    public init(provider: AuthenticationProvider) {
        self.provider = provider
    }

    /// Call once at launch. Attempts to restore a session; sets the
    /// gate to authenticated or unauthenticated accordingly.
    public func start() async {
        state = .checking
        switch await provider.restoreSession() {
        case .success(let account?):
            state = .authenticated(account)
        case .success(nil):
            state = .unauthenticated(lastError: nil)
        case .failure(let error):
            // A restore failure is not shown as a hard error; the user
            // simply needs to sign in. The error is retained for
            // optional display/diagnostics.
            state = .unauthenticated(lastError: error)
        }
    }

    /// Triggered by the "Continue with Google" button.
    public func signIn() async {
        // Keep the current state visible; sign-in presents its own
        // progress UI. Only transition on a definitive outcome.
        switch await provider.signIn() {
        case .success(let account):
            state = .authenticated(account)
        case .failure(let error):
            state = .unauthenticated(lastError: error)
        }
    }

    /// Triggered by sign-out. Returns the gate to the login screen.
    public func signOut() async {
        guard case .authenticated(let account) = state else { return }
        await provider.signOut(account: account)
        state = .unauthenticated(lastError: nil)
    }
}

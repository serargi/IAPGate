import Foundation
import CloudGateCore

/// The authentication gate state that the UI observes on launch.
///
/// This is the single source of truth for "what does the app show":
/// - `.checking`   — verifying stored credentials at launch (brief).
/// - `.unauthenticated` — no valid session; show ONLY the login screen.
/// - `.authenticated`  — a valid session exists; show the app.
///
/// The UI renders exactly one of these and nothing else until a valid
/// session exists, which is the required behavior: no session → login,
/// and nothing more.
public enum SessionState: Equatable, Sendable {
    case checking
    case unauthenticated(lastError: CloudGateError?)
    case authenticated(Account)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

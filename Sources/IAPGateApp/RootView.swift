import SwiftUI
import Auth
import Discovery
import Transport

/// The authentication gate. Renders exactly one of:
/// - a brief spinner while restoring a session,
/// - the login screen when there is no valid session,
/// - the main app when authenticated.
///
/// Nothing beyond the login screen is shown until a valid session
/// exists — the required behavior.
struct RootView: View {
    @Environment(SessionController.self) private var session
    let configError: String?
    let discovery: DiscoveryProviding
    let favoritesStore: FavoritesStore
    let connectionManager: ConnectionManager

    var body: some View {
        switch session.state {
        case .checking:
            CheckingView()
        case .unauthenticated(let lastError):
            LoginView(lastError: lastError, configError: configError)
        case .authenticated(let account):
            MainView(account: account, discovery: discovery,
                     favoritesStore: favoritesStore, connectionManager: connectionManager)
        }
    }
}

private struct CheckingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking your session…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

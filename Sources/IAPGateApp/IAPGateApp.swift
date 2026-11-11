import SwiftUI
import Auth
import Discovery
import Transport
import CloudGateCore

@main
struct IAPGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: SessionController
    private let configError: String?
    private let discovery: DiscoveryProviding
    private let favoritesStore: FavoritesStore
    private let connectionManager: ConnectionManager

    init() {
        // Authentication is delegated to the gcloud CLI: signing in runs
        // `gcloud auth login` (opens the browser), gcloud stores and
        // refreshes the session, and API calls use
        // `gcloud auth print-access-token`. This removes the need for
        // our own OAuth client, client secret, provisioning CLI, and
        // Keychain credential storage. gcloud is already required for
        // IAP connections, so no new dependency is introduced.
        self.favoritesStore = UserDefaultsFavoritesStore()
        self.connectionManager = ConnectionManager()

        guard let runner = GcloudRunner() else {
            // gcloud not found: the app still launches but explains it.
            configError = "gcloud was not found. Install the Google Cloud SDK (https://cloud.google.com/sdk) and reopen the app."
            let empty = DisabledDiscovery()
            self.discovery = empty
            _session = State(initialValue: SessionController(provider: DisabledAuthProvider()))
            return
        }
        configError = nil

        let provider = GcloudAuthProvider(runner: runner)
        let tokenProvider = GcloudAccessTokenProvider(runner: runner)
        let http = URLSessionHTTPClient()
        self.discovery = DiscoveryService(
            resourceManager: ResourceManagerClient(http: http, tokenProvider: tokenProvider),
            compute: ComputeClient(http: http, tokenProvider: tokenProvider))

        _session = State(initialValue: SessionController(provider: provider))
    }

    var body: some Scene {
        WindowGroup {
            RootView(configError: configError, discovery: discovery,
                     favoritesStore: favoritesStore, connectionManager: connectionManager)
                .environment(session)
                .frame(minWidth: 820, minHeight: 520)
                .task { await session.start() }
        }
        .windowResizability(.contentSize)
    }
}

/// App lifecycle for this single-window utility:
/// - Closing the window quits the app (no invisible background process).
/// - On quit, all PTY sessions (gcloud/ssh/tunnel process groups) are
///   torn down so no remote session is left running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Transport.PTYSession.terminateAll()
    }
}

/// Placeholder auth provider used only when gcloud is missing, so the
/// app can still launch and show the configuration error.
private struct DisabledAuthProvider: AuthenticationProvider {
    func restoreSession() async -> Result<Account?, CloudGateError> { .success(nil) }
    func signIn() async -> Result<Account, CloudGateError> {
        .failure(.make(.unexpected, userMessage: "gcloud is not installed."))
    }
    func signOut(account: Account) async {}
}

/// Placeholder discovery used only when gcloud is missing.
private struct DisabledDiscovery: DiscoveryProviding {
    func organizations(accountID: String) async -> Result<[Organization], CloudGateError> { .success([]) }
    func children(accountID: String, parent: String) async -> Result<NodeChildren, CloudGateError> {
        .success(NodeChildren(folders: [], projects: []))
    }
    func projectsWithoutVisibleParent(accountID: String) async -> Result<[Project], CloudGateError> { .success([]) }
    func instances(accountID: String, projectID: String) async -> Result<[Instance], CloudGateError> { .success([]) }
}

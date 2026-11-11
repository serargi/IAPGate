import Foundation
import CloudGateCore

/// Supplies access tokens for Google API calls by asking gcloud.
///
/// gcloud manages the token lifecycle (refresh, reauth), so we simply
/// request a fresh token per call. Tokens are cached briefly in memory
/// to avoid spawning gcloud on every single API request.
public final class GcloudAccessTokenProvider: AccessTokenProviding, @unchecked Sendable {

    private let runner: GcloudAuthProvider.Runner
    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedAt: Date = .distantPast
    private let ttl: TimeInterval

    public init(runner: GcloudAuthProvider.Runner, cacheSeconds: TimeInterval = 120) {
        self.runner = runner
        self.ttl = cacheSeconds
    }

    public func validAccessToken(for accountID: String) async -> Result<String, CloudGateError> {
        if let token = cachedValidToken() { return .success(token) }

        let (output, code) = await runner.run(
            ["auth", "print-access-token", "--quiet"], interactive: false)
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !token.isEmpty else {
            return .failure(.make(
                .authenticationRequired,
                userMessage: "Your Google session has expired. Please sign in again.",
                technicalDetail: "gcloud print-access-token exit \(code)"))
        }
        storeToken(token)
        return .success(token)
    }

    /// Clears the cached token (e.g. after sign-out).
    public func invalidate() {
        lock.lock(); cachedToken = nil; cachedAt = .distantPast; lock.unlock()
    }

    // Synchronous lock sections (never span an `await`).

    private func cachedValidToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let token = cachedToken, Date().timeIntervalSince(cachedAt) < ttl {
            return token
        }
        return nil
    }

    private func storeToken(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        cachedToken = token
        cachedAt = Date()
    }
}

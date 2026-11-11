import Foundation

/// A minimal HTTP transport abstraction.
///
/// Abstracted so token exchange/refresh parsing can be tested without
/// real network access. The production implementation wraps
/// `URLSession`; tests provide a stub that returns canned responses.
public protocol HTTPClient: Sendable {
    /// Performs the request and returns the body data plus the HTTP
    /// status code. Throws only on transport failure (no response).
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// `URLSession`-backed implementation. Uses the system session, which
/// handles TLS validation and system proxy configuration (security
/// rule: do not disable certificate validation).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}

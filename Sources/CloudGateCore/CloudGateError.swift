import Foundation

/// The structured error model for CloudGate.
///
/// Errors carry a stable `kind` for programmatic handling, a
/// user-facing message that is safe to display, and optional technical
/// detail for diagnostics. User-facing messages must never contain
/// secrets; `technicalDetail` is routed only through the redacting
/// diagnostics layer.
public struct CloudGateError: Error, Equatable, Sendable {

    /// A stable classification of the failure. Mirrors the three-level
    /// capability model (visibility / connect authorization / OS auth)
    /// plus transport and local concerns.
    public enum Kind: String, Sendable, CaseIterable {
        // Authentication
        case authenticationRequired
        case authenticationFailed
        case authorizationRevoked
        case tokenExpired

        // Google Cloud authorization / discovery
        case insufficientCloudPermissions
        case apiDisabled
        case discoveryIncomplete
        case resourceNotFound

        // Instance state
        case instanceNotRunning
        case instanceStateUnknown

        // IAP transport
        case iapPermissionDenied
        case iapTunnelFailed
        case firewallBlocksConnectivity
        case localPortUnavailable

        // SSH
        case sshAuthenticationFailed
        case sshHostKeyChanged
        case sshHostKeyUnverified

        // RDP
        case rdpClientNotInstalled
        case rdpConnectionFailed

        // Generic
        case networkTimeout
        case cancelled
        case unexpected
    }

    public let kind: Kind

    /// Safe, localized-at-presentation message. Must not contain
    /// secrets or raw stack traces.
    public let userMessage: String

    /// Optional technical detail for diagnostics. Only ever emitted
    /// through the redacting logger, never shown as a normal
    /// user-facing error.
    public let technicalDetail: String?

    /// Whether retrying could plausibly succeed. Permanent
    /// authorization failures are not retryable.
    public let isRetryable: Bool

    public init(
        kind: Kind,
        userMessage: String,
        technicalDetail: String? = nil,
        isRetryable: Bool = false
    ) {
        self.kind = kind
        self.userMessage = userMessage
        self.technicalDetail = technicalDetail
        self.isRetryable = isRetryable
    }
}

public extension CloudGateError {
    /// Transient conditions where bounded retry with backoff is
    /// reasonable. Authorization failures are intentionally excluded:
    /// retrying a permanent authorization failure never succeeds and
    /// only wastes quota (see workflow/security rules).
    static let retryableKinds: Set<Kind> = [
        .networkTimeout,
        .iapTunnelFailed
    ]

    /// Convenience factory that sets `isRetryable` consistently with
    /// `retryableKinds`.
    static func make(
        _ kind: Kind,
        userMessage: String,
        technicalDetail: String? = nil
    ) -> CloudGateError {
        CloudGateError(
            kind: kind,
            userMessage: userMessage,
            technicalDetail: technicalDetail,
            isRetryable: retryableKinds.contains(kind)
        )
    }
}

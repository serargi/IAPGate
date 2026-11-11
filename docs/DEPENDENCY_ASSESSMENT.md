# Dependency Assessment

Status: Phase 1. Every dependency must be justified here before it is
added (security rule).

## Policy

Before adding any dependency, record: purpose, license, maintenance
status, security implications, impact on app size, and alternatives
considered. Prefer Apple system frameworks.

## Current decision: zero third-party runtime dependencies (target)

The architecture is designed so the core can be built with system
frameworks only:

| Need | System framework | Avoids |
|------|------------------|--------|
| HTTP | URLSession | Alamofire etc. |
| WebSocket (IAP) | URLSessionWebSocketTask | Starscream etc. |
| JSON | Codable | SwiftyJSON etc. |
| Secrets | Keychain Services | third-party keychain wrappers |
| OAuth | Hand-wired PKCE over URLSession + ASWebAuthenticationSession/system browser | heavy OAuth SDKs |
| SSH | System OpenSSH (`/usr/bin/ssh`) | bundled SSH library |

### Note on OAuth libraries

The master prompt says to use an established auth library when
demonstrably appropriate and not to implement crypto primitives from
scratch. PKCE requires only SHA-256 (CryptoKit) and a random verifier
(SecRandom) — both system-provided. We are **not** implementing
cryptographic primitives; we are composing system primitives per the
documented OAuth flow. If the hand-wired flow proves fragile, Google's
`AppAuth-iOS` (Apache-2.0, maintained) is the pre-approved fallback and
will be re-assessed here before adoption.

## Reference projects (studied, NOT linked as dependencies)

These informed the design. None are compiled into CloudGate.

| Project | License | Use |
|---------|---------|-----|
| GoogleCloudPlatform/iap-desktop | Apache-2.0 | Protocol + UX reference |
| cedws/iapc | MIT or GPLv3 | IAP relay protocol reference |
| hazaelsan/ssh-relay | (verify) | Relay protocol reference |
| kvysotskyi/go-iap-mac | (verify) | macOS IAP precedent |

No proprietary code, branding, or assets from any reference product
will be copied. Verify each license before reusing any snippet.

## RDP client (Phase 7)

An external RDP client (e.g., Microsoft Remote Desktop or an
open-source client) will be orchestrated, not bundled. Selection and
its license/security review happen in Phase 7 and will be recorded in
`RDP_INTEGRATION.md`.

# Security Policy

Status: Phase 1 policy. Controls are implemented and verified per
phase; this document is updated as controls land.

Security is an architectural requirement, not a post-hoc feature.
Principles: least privilege, secure defaults, defense in depth,
explicit trust boundaries.

## Trust boundaries

1. **User's Mac** (trusted) — the app, Keychain, local loopback socket.
2. **Google endpoints** (trusted transport, authenticated) — OAuth,
   Cloud APIs, IAP endpoint, over HTTPS/WSS with standard cert
   validation.
3. **Target VM** (semi-trusted) — reached only through IAP; its
   metadata (names, labels) is treated as untrusted input.
4. **External SSH/RDP clients** (local, user-selected) — invoked with
   structured arguments, never a shell.

## Credential handling

- Tokens and other secrets live in the macOS Keychain only.
- Never in UserDefaults, plist, logs, crash reports, or analytics.
- Secrets are never passed as process command-line arguments.

### Authentication model: delegated to gcloud

IAPGate does not run its own OAuth client and stores no Google
credentials. Sign-in is delegated to `gcloud auth login`; the session
is owned, stored, and refreshed by gcloud in `~/.config/gcloud`. Access
tokens are obtained on demand from `gcloud auth print-access-token` and
cached only briefly in memory. Consequently there is no client secret,
no token/credential storage in the app, and no provisioning step — the
earlier self-hosted OAuth (PKCE) design and its "client secret"
exception no longer apply.

## Network

- HTTPS/WSS only; certificate validation never disabled.
- Loopback forwarding sockets bind to `127.0.0.1` only, ephemeral port.
- No unnecessary listeners.
- Expected destinations only (see PRIVACY.md).

## Process execution (SSH/RDP clients)

- Use `Foundation.Process` with arguments passed as an array.
- No shell interpolation; resource names never reach a shell.
- Validate executable paths before launch.
- Apply timeouts; terminate child processes on session end.
- Do not inherit unnecessary environment variables.
- Never execute downloaded binaries or scripts automatically.

## Google Cloud authorization

- Never bypass IAM, IAP, firewall, or org policies.
- Read-only regarding cloud configuration in the initial release.
- No automatic creation of service accounts/projects, no IAM edits,
  no automatic API enablement.

## Logging and diagnostics

- Structured logging with a central redaction layer that strips tokens,
  authorization headers, private keys, and passwords.
- Verbose diagnostics are opt-in.
- Diagnostic export is reviewable and redacted before sharing.

## Storage and retention

- Preferences (non-secret) separated from credentials.
- Cached resource metadata has explicit expiration.
- Connection history has a defined retention policy and is clearable.
- Sign-out deletes stored credentials and can revoke them at Google.

## Distribution

- Plan for Apple Developer ID signing and notarization.
- Evaluate App Sandbox and required entitlements; justify any
  exception (network client, outbound connections, Keychain access).
- No broad entitlements without documented justification.

## Verification per phase

Each phase must demonstrate, with executed tests, that:
- No token appears in logs or plain-text preferences.
- No secret appears in process arguments.
- Loopback sockets never bind to public interfaces.
- Host key verification is enforced (SSH).
- Resources are cleaned up after success, cancellation, and failure.

See `THREAT_MODEL.md` for the threat catalogue and mitigations.

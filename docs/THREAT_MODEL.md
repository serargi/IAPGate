# Threat Model

Status: Phase 1. Reviewed and updated each phase.

Scope: a local macOS desktop app with no vendor backend, talking to
Google endpoints using the user's authorized identity.

## Assets

- OAuth access and refresh tokens.
- SSH private keys (user-managed, never owned by the app).
- RDP credentials (never persisted by the app in plain text).
- Cloud resource metadata (treated as potentially sensitive).

## Threats and mitigations

| # | Threat | Mitigation |
|---|--------|-----------|
| 1 | Malicious local process reads tunnel traffic | Loopback-only bind, ephemeral port, per-session listener, prompt teardown |
| 2 | Compromised/malicious VM metadata (names, labels) injects into shell or UI | Treat as untrusted; structured process args, no shell; escape/encode in UI |
| 3 | Token theft from storage | Keychain only; never in UserDefaults/logs/crash reports |
| 4 | OAuth redirect/authorization-code interception | PKCE (S256), `state` validation, single-use loopback listener |
| 5 | Shell injection via resource names | `Process` with array args; no shell invocation |
| 6 | Local port exposure to the network | Bind `127.0.0.1` only; never `0.0.0.0`; verified by test |
| 7 | SSH host key spoofing / MITM | Enforce host key verification; surface changes; never auto-trust |
| 8 | Compromised or misbehaving RDP client | User-selected trusted client; no secrets in args; tunnel lifecycle isolated |
| 9 | Dependency compromise (supply chain) | Minimal deps; each reviewed for license, maintenance, security; pinned versions |
| 10 | Inadvertent logging of secrets/infra | Central redaction layer; opt-in verbose; reviewable diagnostic export |
| 11 | Token leakage via debug output | No tokens in debug prints; redaction enforced; tested |
| 12 | Abandoned tunnels after crash/cancel | Structured concurrency cancellation; explicit teardown; cleanup tests |
| 13 | Over-broad OAuth scope | Least-privilege scopes; incremental where feasible |
| 14 | Privilege confusion (visible != connectable) | Explicit three-level capability model with distinct diagnostics |

## Non-goals (initial release)

- Defending against a fully compromised local OS/root user.
- Protecting against a malicious user-chosen SSH/RDP client beyond not
  leaking secrets to it.
- Detecting compromise of Google's own endpoints.

## Security tests derived from this model

- No token in logs or plain-text preferences (threats 3, 10, 11).
- No secret in process arguments (threats 3, 5).
- Loopback-only socket binding (threats 1, 6).
- Host key verification enforced (threat 7).
- Cleanup after success/cancel/failure (threat 12).
- Expired-credential handling (threat 4/3).
- Resource-name injection resistance (threats 2, 5).

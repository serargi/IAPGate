# Architecture

Status: Phase 1 proposal. This document records the intended
architecture and the reasoning behind each significant decision.
Items marked **(assumption)** are not yet verified in code; items
marked **(verified)** are backed by cited documentation or source.

## 1. Overview

CloudGate for Mac is a single native macOS application with no vendor
backend. It talks directly to Google's authentication, Google Cloud
APIs, and the IAP tunnel endpoint. SSH and RDP are delivered through
local clients connected to a loopback-bound local forwarding socket.

```
┌────────────────────────────────────────────────────────┐
│                   CloudGate for Mac                      │
│                                                          │
│  SwiftUI (presentation)                                  │
│    │                                                     │
│    ├── AuthenticationProvider  ─── Keychain              │
│    ├── CloudResourceProvider   (Resource Manager + GCE)  │
│    ├── ConnectionManager                                 │
│    │     ├── IAPTransport  (WebSocket, loopback socket)  │
│    │     ├── SSHConnectionProvider (OpenSSH)             │
│    │     └── RDPConnectionProvider (external client)     │
│    ├── SecureCredentialStore (Keychain)                  │
│    ├── PreferencesStore (UserDefaults, non-secret only)  │
│    └── Logging & Diagnostics (redacting)                 │
└───────────────┬──────────────────────────────────────────┘
                │ HTTPS / WSS  (user's authorized identity)
                ▼
┌────────────────────────────────────────────────────────┐
│                     Google Cloud                         │
│  OAuth 2.0 / Identity    accounts.google.com, oauth2     │
│  Resource Manager        cloudresourcemanager.googleapis │
│  Compute Engine          compute.googleapis.com          │
│  IAP TCP forwarding      tunnel.cloudproxy.app (WSS)     │
└────────────────────────────────────────────────────────┘
```

The IAP tunnel and the SSH/RDP client each run as their own
connection/process; the diagram shows logical responsibility, not a
single socket.

## 2. Platform and technology

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Language | Swift | Native, first-class on macOS, no runtime to bundle |
| UI | SwiftUI (AppKit interop where needed) | Native look, dark mode, accessibility for free |
| Concurrency | async/await + structured concurrency | Keeps network work off the main thread |
| HTTP | URLSession | System framework, proxy + TLS handled by OS |
| WebSocket | URLSessionWebSocketTask | System framework; no third-party WS library needed |
| Secrets | Keychain Services | OS-protected credential storage |
| Build | Swift Package Manager + Xcode project | SPM for modules/tests, Xcode for the app target |

Minimum macOS target: **macOS 14 (Sonoma)** (assumption, to confirm
against SwiftUI APIs actually used). Primary architecture Apple
Silicon; Intel supported via a universal binary if no extra
architectural cost.

Electron, Chromium, Node, and bundled web servers are explicitly
excluded (see `product.md`).

## 3. Module boundaries

Each module is an SPM target with a protocol-defined public surface so
it can be mocked in tests and replaced independently.

- **CloudGateCore** — shared models, error model, redaction utilities.
- **Auth** — `AuthenticationProvider`, OAuth PKCE flow, token refresh.
- **CloudAPI** — typed clients for Resource Manager and Compute Engine.
- **Discovery** — `CloudResourceProvider`: hierarchy assembly,
  pagination, dedup, partial-result handling, caching.
- **Transport** — `IAPTransport`: WebSocket relay client + local
  loopback listener.
- **SSH** — `SSHConnectionProvider`: OpenSSH process orchestration,
  host key verification.
- **RDP** — `RDPConnectionProvider`: external client orchestration.
- **Storage** — `SecureCredentialStore` (Keychain) and
  `PreferencesStore` (UserDefaults, non-secret).
- **Diagnostics** — structured logging with redaction.
- **CloudGateApp** — SwiftUI app target wiring modules via dependency
  injection.

Hard rule: **Transport has no dependency on SSH or RDP.** It exposes a
byte stream over a loopback socket; the connection providers consume it.

## 4. Key technical decision: IAP transport without gcloud

The single highest-risk decision. Resolved in favor of a **direct
WebSocket implementation of the IAP relay protocol** (option A in the
master prompt).

Evidence:
- IAP TCP forwarding uses WebSockets to the IAP endpoint
  ([IAP Desktop proxy docs](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Proxy-Configuration)). (verified)
- IAP Desktop, the open-source reference, does **not** depend on gcloud
  or the Cloud SDK
  ([IAP Desktop FAQ](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Frequently-Asked-Questions)). (verified)
- The protocol is a modified **Corp Relay v4 / SSH-over-WebSocket**
  protocol, publicly documented by Chromium's nassh and implemented
  independently by `cedws/iapc` (Go) and `hazaelsan/ssh-relay`
  ([iapc README](https://github.com/cedws/iapc)). (verified)
- A macOS-specific precedent exists: `kvysotskyi/go-iap-mac` manages
  IAP tunnels on macOS without gcloud
  ([go-iap-mac](https://github.com/kvysotskyi/go-iap-mac)). (verified)

Full protocol details and the fallback plan are in
[`IAP_TRANSPORT.md`](IAP_TRANSPORT.md). The transport is isolated
behind the `IAPTransport` protocol, so a fallback (isolated gcloud
subprocess) can be substituted without touching SSH/RDP if the direct
implementation proves unreliable.

## 5. Authentication

OAuth 2.0 **authorization code + PKCE** using a **Desktop app** OAuth
client with a **loopback redirect** (`http://127.0.0.1:<ephemeral>`).
The loopback flow remains supported for desktop apps
([Google loopback migration guide](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration)). (verified)

No client secret is embedded; desktop clients are public clients and
PKCE provides the protection. Tokens live only in Keychain. Details in
[`AUTHENTICATION.md`](AUTHENTICATION.md).

## 6. Resource discovery

Discovery must not assume organization-level visibility. It combines:
- `projects.search` / `projects.list` (Resource Manager) for projects
  reachable through inherited IAM — works even without org listing.
- `organizations.search` and `folders.list` where permitted, to build
  the hierarchy when visible.
- `instances.aggregatedList` (Compute Engine) per project for VMs.

Projects discovered without a visible parent org are surfaced under an
"Accessible projects" group. Partial results and per-node permission
errors are first-class states, not failures. Internal identity is the
stable resource ID, never the display name.

## 7. Capability model

Three distinct capabilities are tracked and reported separately:
1. **Visibility** — can the resource be discovered/listed.
2. **Connect authorization** — IAP + IAM permits establishing a tunnel.
3. **OS authentication** — SSH/RDP login succeeds on the VM.

A failure at any level maps to a specific, understandable diagnostic.

## 8. Threading and lifecycle

All network and process work runs off the main actor. UI state is
updated on `@MainActor`. IAP tunnels are created on demand and torn
down when the session ends, fails, or the app quits. Tunnel cleanup is
guaranteed via structured concurrency cancellation and explicit
teardown in `deinit`/`Task` cancellation handlers.

## 9. Open questions (tracked in KNOWN_LIMITATIONS.md)

- Exact minimum macOS version once SwiftUI APIs are fixed.
- Which OAuth client registration model to ship with (see AUTHENTICATION).
- RDP client selection (see RDP integration, Phase 7).

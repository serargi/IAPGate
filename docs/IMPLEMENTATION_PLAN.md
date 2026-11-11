# Implementation Plan

Status: living document. Reflects actual progress, not aspiration.

## Confirmed product decisions

- **Authentication via gcloud (changed).** Sign-in delegates to
  `gcloud auth login`; API tokens come from
  `gcloud auth print-access-token`. The earlier self-hosted OAuth
  (PKCE) stack — client ID/secret, loopback server, token exchange,
  Keychain credential storage, `iapgate-provision` — has been removed.
  Rationale: no OAuth client to register/ship, which suits open source;
  gcloud is already required for IAP. See AUTHENTICATION.md.
- **Open source:** Apache-2.0 (LICENSE + NOTICE). The repo ships no
  credentials.


- **Connection model (v1): external clients.** SSH opens in Terminal;
  RDP will open the system RDP client. An integrated terminal is a
  medium-term option.
- **IAP transport (SSH): Option B chosen for v1.** SSH connects via
  `gcloud compute ssh --tunnel-through-iap`, isolated behind
  `ConnectionManager`. gcloud handles key propagation, username
  resolution, and the tunnel — this is what made SSH actually work
  end-to-end. The direct-WebSocket transport (Option A: `IAPTunnel`,
  `IAPFrame`, `LoopbackForwarder`) remains implemented and tested, kept
  as the path to a no-gcloud experience later. (See IAP_TRANSPORT.md.)
- **Requirement:** gcloud installed and `gcloud auth login` current.
  If gcloud's session expires, it prompts for reauth in the terminal.
- **Build environment:** logic layer via SwiftPM + Swift Testing now;
  SwiftUI app target and signing/notarization deferred until Xcode is
  available.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | Discovery & Architecture | **Complete** |
| 2 | Native application foundation | **Complete (SwiftUI app + icon)** |
| 3 | Google authentication | **Working (live; session persists; single Keychain vault)** |
| 4 | Resource discovery | **Working (org combobox, lazy folders/subfolders/projects/VMs, search, favorites)** |
| 5 | IAP transport | **Working (WebSocket impl + tested; gcloud used for SSH/RDP)** |
| 6 | SSH | **Working end-to-end (embedded terminal, OS Login username, custom port)** |
| 7 | RDP | **Working (IAP tunnel + external client; Windows credential reset)** |
| 8 | Security & performance | Partial (token cache, session cleanup) |
| 9 | Release | Not started (Developer ID signing + notarization pending) |

## Current app capabilities (verified)

- Google sign-in; session persists across launches; secrets in one
  Keychain vault (read once per launch).
- Organization picker ("Escoge tu organización…"), lazy hierarchy of
  folders → subfolders → projects → VMs, search that preserves the
  tree, navigable favorites (folders and projects).
- VM list with OS detection (Linux/Windows), fixed row height, live
  refresh on project re-select.
- Double-click or right-click to connect over IAP: SSH (Linux) / RDP
  (Windows), with "connect on a custom port". Embedded terminal for
  SSH; external client for RDP; sessions torn down on tab close.
- "Generate Windows credentials" (reset-windows-password) with an
  explicit confirmation warning.
- App icon; launches as a normal macOS app.

## Known limitations / pending

- **Distribution:** app is ad-hoc signed, so macOS prompts for the
  Keychain and warns about an unidentified developer. Developer ID
  signing + notarization (Phase 9) removes both. Needs an Apple
  Developer account.
- **gcloud dependency:** SSH/RDP use the installed gcloud; a stale
  gcloud session prompts for reauth inside the terminal. The direct
  WebSocket transport (no gcloud) exists and is tested but is not the
  default path.
- **OS Login:** projects without OS Login get their SSH key published
  to project metadata (a Google-audited "sensitive action"). By
  design we keep connecting; enabling OS Login org-wide removes it.
- **Embedded terminal** is a basic emulator; full-screen TUIs (vim,
  htop) are out of scope.

## Phase 1 — Discovery & Architecture

Goal: resolve critical technical risks before writing app code.

- [x] Inspect repository (empty workspace).
- [x] Research IAP transport feasibility without gcloud.
- [x] Research OAuth native-app flow and scopes.
- [x] Establish steering rules (product, security, engineering, workflow).
- [x] ARCHITECTURE.md
- [x] IAP_TRANSPORT.md (decision: direct WebSocket, option A)
- [x] AUTHENTICATION.md
- [x] SECURITY.md
- [x] THREAT_MODEL.md
- [x] PRIVACY.md
- [x] DEPENDENCY_ASSESSMENT.md
- [x] PRODUCT_RESEARCH.md
- [x] KNOWN_LIMITATIONS.md
- [x] IMPLEMENTATION_PLAN.md (this file)
- [x] Scaffold SPM package + first module skeletons (bridge into Phase 2)

Exit criteria: critical risks investigated with cited evidence;
architecture recommended; no large app code before risks resolved. Met.

## Phase 2 — Native application foundation

- [x] SPM workspace with core modules as targets.
- [x] Error model (`CloudGateError`) with retry policy.
- [x] Redaction utility (`Redactor`) + tests.
- [x] Validated `ResourceIdentifier` (injection-safe) + tests.
- [x] Redacting structured logger (`RedactingLogger`) + tests.
- [x] Test infrastructure (TestKit harness) — `swift run CloudGateTests`
      passes (24 tests).
- [x] `PreferencesStore` (non-secret, UserDefaults-backed) + tests.
- [ ] Localization scaffold (en, es) — string catalog (needs app target).
- [ ] App lifecycle + navigation shell (SwiftUI) — needs Xcode target.
- [ ] Empty-state views.
- Exit: build + tests pass (done for logic layer); app shell and
  localization catalog pending Xcode availability.

### Environment note
This machine has Command Line Tools only (no full Xcode). Library
modules and logic tests build and run via SwiftPM. XCTest (Xcode-only)
and the Swift Testing macro plugin are both unavailable/unreliable
here, so tests use the in-repo **TestKit** harness run as an
executable. The SwiftUI app target and localization catalog require
Xcode and are deferred; see `docs/DEVELOPMENT.md`.

## Phase 3 — Google authentication

Offline/testable parts done; network + UI parts pending (need a
registered OAuth client ID and Xcode).

- [x] PKCE generation (S256) + RFC 7636 test vector.
- [x] Authorization URL builder + callback validation (state/CSRF).
- [x] `SecureCredentialStore` protocol + Keychain + in-memory double.
- [x] `Account` / `TokenSet` model (secret vs. non-secret separation).
- [x] **Auth gate**: `SessionState` + `SessionController`
      (checking → unauthenticated → authenticated) with tests.
- [x] Loopback HTTP listener for the redirect (`LoopbackRedirectServer`).
- [x] System-browser launch (`BrowserLauncher`) + token exchange
      (`TokenService` over `HTTPClient`/`URLSession`).
- [x] Token refresh (+ refresh-token preservation). Revocation network
      call still pending; local deletion done.
- [x] ID token identity extraction (`IDTokenClaims`).
- [x] Full provider wiring (`GoogleAuthenticationProvider`), end-to-end
      tested with doubles.
- [x] **OAuth client ID** in Google Cloud Console (desktop app).
- [x] Secure provisioning (`iapgate-provision`): client ID/secret read
      from stdin with echo off, stored in Keychain. Never in env vars,
      args, source, or shell history.
- [x] `SecureConfigStore` (Keychain) + in-memory double.
- [x] SwiftUI app shell + gate (`RootView`) + login screen
      ("Iniciar sesión con Google") bound to `SessionController`.
- [x] `IAPGate.app` bundle + ad-hoc signing script (`make-app.sh`).
- [x] **Live sign-in verified** against Google with a real account:
      browser → consent → token exchange (with desktop client secret)
      → Keychain → authenticated session shown. Read-only scope.
- [ ] Token revocation network call on sign-out.
- [ ] Multi-account switching UI; persist AccountDirectory to disk.
- [ ] Developer ID signing + notarization (release phase).
- [ ] Google OAuth app verification before public release.
- Tests: 65 passing total.

### Milestone note
This satisfies the product requirement: on launch with no session the
app shows only the login; after Google sign-in it shows the app. The
OAuth secret for the desktop client lives only in the Keychain
(documented exception in SECURITY.md); PKCE is the real protection.

## Phase 4 — Resource discovery

- [ ] Resource Manager + Compute Engine clients.
- [ ] Hierarchy assembly with partial results + dedup.
- [ ] Pagination, caching w/ expiry, cancellation, search/filter/sort.
- [ ] Capability model (visibility vs connect vs OS auth).
- [ ] Tests with mocked API responses.

## Phase 5 — IAP transport

- [ ] WebSocket relay client (validate corp-relay-v4 mapping live).
- [ ] Loopback listener, ephemeral port, collision handling.
- [ ] Lifecycle: connect, cancel, timeout, cleanup.
- [ ] Error taxonomy (authz, API disabled, firewall, unreachable).
- [ ] Mock-transport tests + optional live integration test.

## Phase 6 — SSH

- [ ] OpenSSH orchestration via Process (array args, no shell).
- [ ] Host key verification enforced; change detection.
- [ ] Session lifecycle + diagnostics; optional SFTP.

## Phase 7 — RDP

- [ ] Select + document external RDP client.
- [ ] Tunnel kept alive for session; cleanup after.
- [ ] Diagnostics when client missing/misconfigured.

## Phase 8 — Security & performance

- [ ] Security test suite (no-leak, loopback-only, injection, cleanup).
- [ ] Dependency audit.
- [ ] Measure cold start, idle CPU/mem, discovery latency, bundle size,
      tunnel cleanup latency.

## Phase 9 — Release

- [ ] Icon, versioning, signing, notarization, install docs, notes.

## Technical risks (ranked)

| Risk | Severity | Mitigation / status |
|------|----------|---------------------|
| IAP relay protocol specifics drift from docs | High | Isolated behind IAPTransport; gcloud fallback (Option B) ready |
| OAuth scope can't be minimized for connect | Medium | Documented; broad scope only where IAP requires it |
| Workspace orgs block third-party OAuth client | Medium | BYO client-ID option under consideration (Q3) |
| RDP session-termination detection unreliable | Medium | Document limitation; safest practical workflow |
| URLSessionWebSocketTask insufficient for relay | Medium | Validate early in Phase 5; fallback to Option B |
| App Sandbox vs. Process(ssh) entitlements | Medium | Evaluate in Phase 2/9; document exceptions |

## Completed / remaining / blockers

- Completed: Phase 1 documentation and decisions.
- Remaining: Phase 1 scaffolding bridge, then Phases 2–9.
- Blockers: none for Phase 2; test GCP account needed for Phases 3/5.

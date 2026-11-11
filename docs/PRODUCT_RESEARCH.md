# Product Research

Status: Phase 1. Enough research to make informed decisions; not an
exhaustive competitive study.

## Reference products

### IAP Desktop (open source, Windows)
GoogleCloudPlatform/iap-desktop — Apache-2.0.

Findings (from public docs, summarized for licensing compliance):
- Manages IAP TCP tunnels automatically and isolates them from other
  users/programs.
  [README](https://github.com/GoogleCloudPlatform/iap-desktop/blob/master/README.md)
- Does **not** depend on gcloud or the Cloud SDK.
  [FAQ](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Frequently-Asked-Questions)
- Tunnels run over WebSockets.
  [Proxy Configuration](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Proxy-Configuration)
- For Linux it manages an SSH key automatically (ECDSA P-256), stored
  non-exportably, and publishes it with a 30-day expiry.
  [Connect Linux](https://googlecloudplatform.github.io/iap-desktop/connect-linux/),
  [jpassing blog](https://jpassing.com/2021/02/27/using-iap-desktop-for-zero-trust-ssh-access/)
- Requires the broad cloud-platform scope for IAP tunneling.
  [Installation](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Installation/0a6fd8ff63af52108b454a617c9fdef2d13ec6fb)

Takeaways for CloudGate:
- The no-gcloud WebSocket approach is proven; adopt it (Option A).
- Automatic SSH key management with expiry is a strong UX pattern, but
  our security rules require explicit user consent before generating or
  publishing keys — so this is opt-in, not automatic, in v1.

### Ostgate IAP Desktop for Mac (commercial)
A macOS product in the same space. Used as a UX/feature reference only.
No proprietary code, branding, or UI is copied. (Public marketing page;
not independently verified here.)

### Other implementations studied
- `cedws/iapc` (Go) — confirms IAP uses a modified Corp Relay v4
  (SSH-over-WebSocket) protocol. [repo](https://github.com/cedws/iapc)
- `hazaelsan/ssh-relay` — independent relay protocol implementation.
- `kvysotskyi/go-iap-mac` — macOS IAP tunnel manager precedent.

## Feature comparison (target vs references)

| Capability | IAP Desktop (Win) | CloudGate v1 target |
|------------|-------------------|---------------------|
| No gcloud dependency | Yes | Yes |
| IAP over WebSocket | Yes | Yes |
| SSH over IAP | Yes | Yes (P0) |
| RDP over IAP | Yes | Yes (P1) |
| Multi-account | Yes | Yes (P1) |
| Partial-hierarchy discovery | Yes | Yes (P0) |
| macOS native | No (Windows) | Yes |
| Auto SSH key publish | Automatic | Opt-in (consent) |

## Opportunities / improvements for CloudGate

- Clean, minimal native macOS experience vs. a connection-manager-heavy
  UI.
- Explicit three-level capability diagnostics (visibility / connect /
  OS auth) to cut troubleshooting time.
- Spanish + English from day one.

## Known limitations observed

- IAP tunneling realistically needs the broad cloud-platform scope;
  truly minimal scoping may not be possible for the connect path.
  Tracked in AUTHENTICATION.md and KNOWN_LIMITATIONS.md.
- RDP has no native macOS API; an external client is required.

## Licensing considerations

- IAP Desktop is Apache-2.0; iapc is MIT/GPLv3. We treat all as
  references. Any snippet reuse requires per-file license review and
  attribution. Default stance: original implementation.

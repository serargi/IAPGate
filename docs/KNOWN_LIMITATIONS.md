# Known Limitations and Open Questions

Status: living document. Updated every phase. Items here are explicitly
**not** claimed as resolved.

## Open technical questions

1. **Minimum macOS version** — not finalized; depends on the exact
   SwiftUI/AppKit APIs used. Current working assumption: macOS 14.
2. **OAuth scope granularity** — whether read-only discovery can use
   `cloud-platform.read-only` while connection requests the broader
   `cloud-platform` scope incrementally. References suggest IAP
   tunneling needs the broad scope. To verify in Phase 3/5.
3. **OAuth client registration model** — ship a built-in desktop client
   ID vs. require users/orgs to supply their own (matters for Workspace
   orgs that restrict third-party OAuth apps). Product + verification
   decision.
4. **IAP relay frame details** — the protocol is documented
   (corp-relay-v4) but CloudGate's exact frame/ACK/reconnect mapping is
   an assumption until validated against a live tunnel in Phase 5.
5. **RDP client selection** — which external client(s) to support and
   how reliably session termination can be detected. Phase 7.
6. **Intel support** — universal binary feasibility to confirm; no
   extra architectural cost is the bar.

## Assumptions not yet verified in code

- `projects.search` returns projects reachable via inherited IAM even
  without organization listing permission.
- `instances.aggregatedList` is the right call for per-project VM
  discovery with partial-permission handling.
- `URLSessionWebSocketTask` is sufficient for the IAP relay (including
  the `Authorization` header and binary framing) without a third-party
  WebSocket library.

## Deferred scope (intentionally excluded from v1)

- Kubernetes, database management, firewall rule editing, IAM
  administration, infrastructure deployment.
- Embedded RDP engine (external client only in v1).
- Integrated SSH terminal (external OpenSSH first; integrated terminal
  is a medium-term option — the chosen v1 model is external clients).

## Blockers

- None currently block Phase 2. Phases 3 and 5 require a test Google
  account/project and, for connect testing, a VM with an IAP-allow
  firewall rule from `35.235.240.0/20`.

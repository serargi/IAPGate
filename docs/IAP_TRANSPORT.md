# IAP Transport Decision

Status: Phase 1 decision record. Resolves the project's highest
technical risk.

## Goal

Establish IAP TCP forwarding tunnels to Compute Engine instances from
the user's Mac, without requiring a manually installed gcloud CLI, and
without routing traffic through any application-owned server.

## Options evaluated

| Option | Description | Verdict |
|--------|-------------|---------|
| A | Direct WebSocket implementation of the IAP relay protocol | **Chosen** |
| B | Isolated subprocess calling the official gcloud CLI | Fallback only |
| C | Reuse another maintained library | Reference, not a runtime dep |

## Decision: Option A (direct WebSocket)

### Evidence

- IAP TCP forwarding tunnels use WebSockets.
  [IAP Desktop — Proxy Configuration](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Proxy-Configuration)
- The open-source reference (IAP Desktop) does not depend on gcloud or
  the Cloud SDK.
  [IAP Desktop — FAQ](https://github.com/GoogleCloudPlatform/iap-desktop/wiki/Frequently-Asked-Questions)
- IAP speaks a modified **Corp Relay v4** (SSH-over-WebSocket) protocol,
  publicly documented and independently implemented.
  [cedws/iapc](https://github.com/cedws/iapc),
  [hazaelsan/ssh-relay](https://github.com/hazaelsan/ssh-relay),
  Chromium nassh relay-protocol.md (`corp-relay-v4`).
- A macOS implementation precedent exists.
  [kvysotskyi/go-iap-mac](https://github.com/kvysotskyi/go-iap-mac)

Content above was summarized from the cited sources for licensing
compliance.

### Why A over B

- No external runtime dependency; the user installs nothing extra.
- Full control over the connection lifecycle, cancellation, cleanup,
  and diagnostics — all required by the security rules.
- `URLSessionWebSocketTask` (system framework) covers the WebSocket
  layer, including system proxy and TLS handling, so no third-party
  WebSocket dependency is introduced.

### Why keep B as a fallback

If the direct implementation proves unreliable against protocol
changes, an isolated, well-documented integration with the official
gcloud `start-iap-tunnel` command can be substituted behind the same
`IAPTransport` protocol. The user experience stays graphical either
way. This fallback must be documented and gated behind the transport
interface; it must never leak into SSH/RDP code.

## Protocol (verified)

Confirmed against the reference implementation
[cedws/iapc `iap/iap.go`](https://github.com/cedws/iapc) (MIT/GPLv3),
which is itself derived from gcloud's source. Values below are what
IAPGate implements.

- **Endpoint**: `wss://tunnel.cloudproxy.app/v4/connect`
- **WebSocket subprotocol**: `relay.tunnel.cloudproxy.app`
- **Headers**: `Origin: bot:iap-tunneler`,
  `Authorization: Bearer <access-token>`
- **Query params**: `project`, `zone`, `instance`, `interface` (`nic0`),
  `port` (e.g. `22` for SSH). Host/region/group variants exist for
  BeyondCorp but are not used in v1.
- **Framing** (binary WebSocket messages, big-endian): a `uint16` tag
  followed by a tag-specific payload:
  - `0x0001` SUCCESS — `uint32 len` + `len` bytes session ID. Sent by
    the relay first; marks the tunnel connected.
  - `0x0004` DATA — `uint32 len` + `len` bytes of tunneled payload.
  - `0x0007` ACK — `uint64` total bytes received so far.
  - Unknown tags are ignored.
- **Max frame size**: 16384 bytes; outgoing data is chunked to this.
- **ACK policy**: after receiving > 2×16384 unacked bytes, send an ACK
  with the running received-byte count.
- Retransmission is unnecessary (the WebSocket rides TCP).

On close/failure the local loopback socket and the WebSocket are both
torn down. No reconnect/resume in v1 (a dropped tunnel ends the
session with a clear diagnostic).

Content above was summarized from the cited source for licensing
compliance; the implementation is original Swift.

## Local forwarding socket

- Bind to `127.0.0.1` (loopback) only. Never `0.0.0.0`.
- Use an ephemeral port chosen by the OS; detect and avoid collisions.
- One listener per active session; closed on session end.
- No private keys or credentials are ever handed to the transport
  layer — it moves opaque bytes only.

## Firewall prerequisite (user-side, documented not automated)

The target VPC must allow ingress on the target port from the IAP
range `35.235.240.0/20`. CloudGate will detect connection failures and
surface this as a specific diagnostic; it will **not** create or modify
firewall rules.

## Acceptance criteria (Phase 5)

- A tunnel can be established to a reachable instance.
- Local socket binds to loopback with an ephemeral port.
- Cancellation and failure both release socket + WebSocket promptly.
- No abandoned tunnels remain after the session ends.
- Authorization, API-disabled, and firewall errors are distinguished.

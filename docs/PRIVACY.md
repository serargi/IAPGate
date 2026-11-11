# Privacy

Status: Phase 1 policy.

CloudGate operates directly from the user's Mac. There is no
application-owned cloud infrastructure and no mandatory account with
the application vendor.

## What leaves the Mac, and to where

Network traffic is limited to:

| Destination | Purpose |
|-------------|---------|
| Google OAuth / Identity endpoints | Sign-in, token refresh/revocation |
| Google Resource Manager API | Discover orgs, folders, projects |
| Google Compute Engine API | Discover VM instances |
| Google IAP tunnel endpoint (`tunnel.cloudproxy.app`) | IAP TCP forwarding |
| User-selected SSH/RDP client | Connect to the target VM over the tunnel |

No other destinations. No third-party analytics, advertising, or
tracking SDKs in the initial release.

## Telemetry

None by default. If telemetry is ever added it must be: off by
default, documented, consent-gated, free of credentials and
infrastructure detail, and fully disableable.

## What is stored locally

| Data | Location | Notes |
|------|----------|-------|
| Access / refresh tokens | Keychain | Deleted on sign-out; revocable |
| Account identifiers + display metadata | UserDefaults | Non-secret only |
| Preferences | UserDefaults | Theme, language, defaults |
| Favorites | UserDefaults | Stable resource IDs |
| Recent connections | Local store | Defined retention, clearable |
| Cached resource metadata | Local cache | Explicit expiration, clearable |

## What is never stored

- VM passwords.
- Private keys copied from other programs.
- Infrastructure metadata retained indefinitely.

## User controls

- Sign out: deletes stored credentials and can revoke authorization.
- Clear recent connections.
- Clear cached metadata.

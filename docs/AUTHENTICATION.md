# Authentication

Status: implemented. IAPGate delegates authentication to the Google
Cloud CLI (`gcloud`) instead of running its own OAuth client.

## Why gcloud-based auth

An earlier design ran a full OAuth 2.0 (authorization code + PKCE)
flow with its own client ID/secret, loopback redirect server, token
exchange, and Keychain storage. That required every user (or
organization) to register and provision an OAuth client, which is
awkward — especially for an open-source app that must not ship
credentials.

Since gcloud is already required for IAP connectivity, we reuse it for
sign-in too. This removes the OAuth client, the client secret, the
provisioning step, and all credential storage from IAPGate. gcloud owns
the session and its refresh.

## Flow

- **Sign in** (`GcloudAuthProvider.signIn`): runs `gcloud auth login`,
  which opens the system browser for Google's standard sign-in. On
  success, the active account is read from
  `gcloud config get-value account`.
- **Restore session** (on launch): if `gcloud config get-value account`
  returns an account and `gcloud auth print-access-token` succeeds, the
  user is considered signed in — no prompt needed.
- **API tokens** (`GcloudAccessTokenProvider`): obtained from
  `gcloud auth print-access-token`, cached in memory for a short TTL to
  avoid spawning gcloud on every API call.
- **Sign out**: runs `gcloud auth revoke <account>`.

The `Account` identity is the account email (what gcloud reports).

## What IAPGate stores

Nothing secret. The Google session lives in gcloud's own store
(`~/.config/gcloud`). IAPGate keeps only non-secret preferences and
favorites in UserDefaults, keyed by the account email.

## Permissions / scopes

Scopes are whatever the user's gcloud login was granted (by default the
broad `cloud-platform` scope gcloud requests). IAPGate does not request
scopes itself. The user still needs the relevant IAM permissions on the
Google Cloud side (resource viewing; `roles/iap.tunnelResourceAccessor`
to connect).

## Session expiry

If gcloud's session expires or is revoked,
`gcloud auth print-access-token` fails and IAPGate reports that the
session expired; signing in again from the app re-runs
`gcloud auth login`.

## Trade-off

This makes gcloud a hard dependency for authentication (not only for
connectivity). A future gcloud-free mode would reintroduce a direct
OAuth flow; the building blocks for the direct IAP transport already
exist (see IAP_TRANSPORT.md), but direct OAuth is intentionally not part
of the current design.

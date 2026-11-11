# Releasing IAPGate

This document describes how to cut a release of IAPGate and, optionally,
how to sign and notarize it so end users can open it without Gatekeeper
warnings.

## Current state (honest status)

- Builds are **ad-hoc signed** (`codesign --sign -`). This is enough to
  run the app locally, but macOS Gatekeeper will warn that the app is
  "from an unidentified developer" the first time a downloaded copy is
  opened. Users work around this with right-click -> Open (documented in
  the README).
- The app is **not** yet signed with a Developer ID or notarized,
  because that requires a paid Apple Developer Program membership. Until
  that is done, the Gatekeeper warning is expected.

## 1. Build and package

```sh
./scripts/make-app.sh release
```

This produces:

- `build/IAPGate.app` — the app bundle (ad-hoc signed).
- `build/IAPGate.zip` — a zip of the bundle (via `ditto`), suitable for
  attaching to a GitHub Release.

Before packaging, run the test suite and confirm it passes:

```sh
swift build
swift run CloudGateTests
```

## 2. Create the GitHub Release

1. Tag the commit (for example `git tag v0.1.0 && git push --tags`).
2. On GitHub, draft a new Release from that tag.
3. Attach `build/IAPGate.zip` as a release asset. The README's download
   instructions point users at this asset.

## 3. (Optional) Developer ID signing + notarization

This removes the Gatekeeper warning for downloaded copies. It requires:

- A paid **Apple Developer Program** membership.
- A **Developer ID Application** certificate installed in your login
  keychain (create it in the Apple Developer portal, then download and
  double-click it, or let Xcode manage it).
- An app-specific password, or an App Store Connect API key, stored in a
  notarytool keychain profile.

Check which signing identities are available:

```sh
security find-identity -v -p codesigning
```

### Sign with Developer ID

Re-sign the bundle with your Developer ID identity and a hardened
runtime (notarization requires the hardened runtime):

```sh
codesign --force --deep --options runtime --timestamp \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    build/IAPGate.app
```

Then repackage the zip from the signed bundle:

```sh
( cd build && rm -f IAPGate.zip && ditto -c -k --keepParent IAPGate.app IAPGate.zip )
```

### Notarize

Store credentials once (interactive; it does not echo the password):

```sh
xcrun notarytool store-credentials iapgate-notary \
    --apple-id "you@example.com" \
    --team-id "TEAMID"
```

Submit and wait:

```sh
xcrun notarytool submit build/IAPGate.zip \
    --keychain-profile iapgate-notary --wait
```

### Staple

On success, staple the ticket to the app so it validates offline, then
re-zip the stapled bundle for distribution:

```sh
xcrun stapler staple build/IAPGate.app
( cd build && rm -f IAPGate.zip && ditto -c -k --keepParent IAPGate.app IAPGate.zip )
```

Verify Gatekeeper acceptance:

```sh
spctl --assess --type execute --verbose build/IAPGate.app
```

A notarized, stapled `IAPGate.zip` opens without the unidentified
developer warning. Upload that zip to the GitHub Release.

## Notes

- Never pass signing passwords or API keys as plain command-line
  arguments in scripts or CI logs; use a notarytool keychain profile or
  an App Store Connect API key file with restricted permissions.
- `make-app.sh` only performs ad-hoc signing. Developer ID signing and
  notarization are intentionally manual, since they depend on secrets
  and a paid account that must not live in the repository.

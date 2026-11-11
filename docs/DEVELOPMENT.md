# Development

## Requirements

- macOS 14+ (target).
- Swift 6 toolchain. The library modules and tests build with the
  Command Line Tools alone.
- **Xcode is required** to build the SwiftUI app target and to run
  XCTest-based UI tests. The current environment has Command Line
  Tools only, so:
  - XCTest is unavailable (it ships with Xcode).
  - The Swift Testing macro plugin (`TestingMacros`) does not load
    reliably under Command Line Tools and failed intermittently.
  - Therefore tests use a tiny in-repo harness, **TestKit**, compiled
    into a plain executable (`CloudGateTests`). No XCTest, no macros.
  - The app target (`CloudGateApp`) and any UI tests are added once
    Xcode is available. Logic tests can migrate to XCTest/Swift
    Testing then without changing the code under test.

## Layout

```
Package.swift            SwiftPM manifest (libraries, app, test exe)
Sources/
  CloudGateCore/         error model, redaction, identifiers, prefs
  Diagnostics/           redacting structured logger
  Auth/                  gcloud-based sign-in, token provider, session
  Discovery/             Resource Manager + Compute clients, favorites
  Transport/             IAP relay (WebSocket) + gcloud connection mgr
  IAPGateApp/            SwiftUI app (the `IAPGateApp` executable)
  TestKit/               minimal assertion + runner harness
  CloudGateTests/        test suites (executable target)
docs/                    architecture, security, planning
scripts/make-app.sh      packages the .app bundle
```

## Build and test

```sh
swift build                 # compiles all targets
swift run CloudGateTests    # builds + runs the test suites
./scripts/make-app.sh debug # packages build/IAPGate.app
open build/IAPGate.app
```

Current status: build and tests pass. A benign linker warning about
Command Line Tools framework search paths may appear and does not
affect the result.

## Conventions

- New modules are SPM targets with a protocol-defined public surface.
- Security-sensitive logic ships with tests in the same change.
- Never log secrets; route technical detail through `RedactingLogger`.
- Reference resources by `ResourceIdentifier`, not display names.

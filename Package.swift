// swift-tools-version: 6.0
import PackageDescription

// Note on testing: this environment has Command Line Tools only (no
// full Xcode), so XCTest is unavailable, and the Swift Testing macro
// plugin (TestingMacros) fails to load reliably here. To keep tests
// runnable and verifiable, tests are compiled into a plain executable
// target (`CloudGateTests`) using a small in-repo assertion harness
// (`TestKit`). Run with: `swift run CloudGateTests`.
// When Xcode is available, these can be migrated to XCTest/Swift
// Testing targets without changing the code under test.
let package = Package(
    name: "CloudGate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CloudGateCore", targets: ["CloudGateCore"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "Discovery", targets: ["Discovery"]),
        .library(name: "Transport", targets: ["Transport"]),
        .executable(name: "IAPGateApp", targets: ["IAPGateApp"])
    ],
    targets: [
        // Shared models, error model, redaction utilities.
        .target(
            name: "CloudGateCore"
        ),
        // Structured logging with sensitive-data redaction.
        .target(
            name: "Diagnostics",
            dependencies: ["CloudGateCore"]
        ),
        // Authentication: gcloud-based sign-in, session state, and the
        // access-token provider used for Google API calls.
        .target(
            name: "Auth",
            dependencies: ["CloudGateCore"]
        ),
        // GCP resource discovery: orgs, projects, Compute instances.
        .target(
            name: "Discovery",
            dependencies: ["CloudGateCore", "Auth"]
        ),
        // IAP TCP forwarding transport + SSH connection management.
        .target(
            name: "Transport",
            dependencies: ["CloudGateCore", "Auth"]
        ),
        // Minimal assertion + runner harness (no XCTest / no macros).
        .target(
            name: "TestKit"
        ),
        // SwiftUI macOS app: the authentication gate + login screen.
        .executableTarget(
            name: "IAPGateApp",
            dependencies: ["Auth", "Discovery", "Transport", "CloudGateCore", "Diagnostics"],
            resources: [
                // Official "Sign in with Google" button asset (Google
                // brand guidelines). Shipped as an asset catalog so the
                // app loads it natively via Image(_:bundle:).
                .process("Resources/Assets.xcassets")
            ]
        ),
        // Test executable. Builds and runs without Xcode.
        .executableTarget(
            name: "CloudGateTests",
            dependencies: ["TestKit", "CloudGateCore", "Diagnostics", "Auth", "Discovery", "Transport"]
        )
    ]
)

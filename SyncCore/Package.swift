// swift-tools-version: 5.9
import PackageDescription

// SyncCore is the *pure* core of DoIT (AppSpec §7 "pure logic cores").
// It depends on Foundation ONLY — no SwiftUI, no SwiftData, no networking.
// Everything time-related goes through the `Clock` protocol (no direct `Date()`),
// so the conflict resolver and sync logic are deterministic and unit-testable.
// It mirrors the backend contract in DoItAi-api/DoIT-ApiSpec.md (§5, §6) field-for-field.
let package = Package(
    name: "SyncCore",
    platforms: [
        // iOS 17+ is the product floor (AppSpec). macOS is listed so `swift test`
        // runs on a dev Mac without an Xcode app target.
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SyncCore", targets: ["SyncCore"])
    ],
    dependencies: [
        // Intentionally empty. SyncCore must resolve & build fully offline.
    ],
    targets: [
        .target(
            name: "SyncCore",
            dependencies: [],
            swiftSettings: [
                // Opt into strict Swift 6 concurrency checking even while building
                // with the Swift 5.9 language mode, so Sendable issues surface early.
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SyncCoreTests",
            dependencies: ["SyncCore"]
        )
    ]
)

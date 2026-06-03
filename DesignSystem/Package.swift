// swift-tools-version: 5.9
import PackageDescription

// DesignSystem holds DoIT's semantic design tokens (AppSpec §11): a `Theme` with semantic color
// tokens, a 4-pt spacing scale, and corner radii, consumed via the SwiftUI Environment. Minimal by
// design for Phase 0 — real components (TaskRow, PriorityChip, …) land in later phases.
// Dependency-free so it resolves and builds fully offline.
let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [],
    targets: [
        .target(name: "DesignSystem", dependencies: []),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NodeClubTracker",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "NodeClubTrackerCore", targets: ["NodeClubTrackerCore"]),
        .executable(name: "NodeClubTracker", targets: ["NodeClubTracker"]),
    ],
    targets: [
        // Pure logic: models, stores, formatting. No UI imports; runs anywhere and tests fast.
        .target(
            name: "NodeClubTrackerCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // The menu bar app itself: SwiftUI scenes + views only.
        .executableTarget(
            name: "NodeClubTracker",
            dependencies: ["NodeClubTrackerCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "NodeClubTrackerCoreTests",
            dependencies: ["NodeClubTrackerCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)

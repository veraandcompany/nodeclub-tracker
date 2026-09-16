// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Taskbar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TaskbarCore", targets: ["TaskbarCore"]),
        .executable(name: "Taskbar", targets: ["Taskbar"]),
    ],
    targets: [
        // Pure logic: models, stores, formatting. No UI imports; runs anywhere and tests fast.
        .target(
            name: "TaskbarCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        // The menu bar app itself: SwiftUI scenes + views only.
        .executableTarget(
            name: "Taskbar",
            dependencies: ["TaskbarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TaskbarCoreTests",
            dependencies: ["TaskbarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)

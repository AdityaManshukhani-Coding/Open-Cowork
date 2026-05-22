// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenCowork",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenCowork",
            targets: ["OpenCowork"]
        )
    ],
    dependencies: [
        // No external dependencies — all Apple frameworks (SwiftUI, AppKit,
        // Accessibility, ScreenCaptureKit, CGEvent, SQLite) are built into
        // the macOS SDK and require no additional packages.
    ],
    targets: [
        .executableTarget(
            name: "OpenCowork",
            path: "Sources/OpenCowork"
        )
    ]
)

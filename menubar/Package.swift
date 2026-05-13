// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenCowork",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "OpenCowork",
            exclude: [
                "Resources/OpenCowork.entitlements",
                "Info.plist"
            ]
        )
    ]
)
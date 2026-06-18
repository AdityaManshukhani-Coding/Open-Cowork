import ProjectDescription

let project = Project(
    name: "OpenCowork",
    targets: [
        .target(
            name: "OpenCowork",
            destinations: .macOS,
            product: .app,
            bundleId: "com.opencode.opencowork",
            deploymentTargets: .macOS("12.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": false,
                "NSAccessibilityUsageDescription": "Open Cowork requires Accessibility permission to observe your screen and simulate mouse clicks and keystrokes.",
                "NSScreenCaptureUsageDescription": "Open Cowork requires Screen Recording permission to capture screenshots for the AI visual reasoning loop.",
                "NSAppleEventsUsageDescription": "Open Cowork requires permission to send events to other native apps to control them.",
                "NSMicrophoneUsageDescription": "Open Cowork requires Microphone access for optional local voice task input."
            ]),
            sources: [
                "Sources/**"
            ],
            resources: [
                "Resources/**"
            ]
        )
    ]
)

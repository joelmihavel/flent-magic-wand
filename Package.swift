// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BGRemover",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BGRemover",
            dependencies: [
                "KeyboardShortcuts",
            ],
            path: "App",
            resources: [
                .copy("../Resources"),
            ]
        ),
    ]
)

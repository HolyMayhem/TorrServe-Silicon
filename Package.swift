// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TorrServerManager",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(
            name: "TorrServerManager",
            targets: ["TorrServerLauncher"]
        ),
        .library(
            name: "TorrServerUI",
            targets: ["TorrServerKit"]
        )
    ],
    targets: [
        .target(
            name: "TorrServerKit",
            path: "Sources"
        ),
        .executableTarget(
            name: "TorrServerLauncher",
            dependencies: ["TorrServerKit"],
            path: "Launcher"
        ),
        .testTarget(
            name: "TorrServerManagerTests",
            dependencies: ["TorrServerKit"],
            path: "Tests/TorrServerManagerTests"
        )
    ]
)

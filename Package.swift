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
            targets: ["TorrServerManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TorrServerManager",
            path: "Sources"
        ),
        .testTarget(
            name: "TorrServerManagerTests",
            dependencies: ["TorrServerManager"],
            path: "Tests/TorrServerManagerTests"
        )
    ]
)

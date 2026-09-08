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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        )
    ],
    targets: [
        .executableTarget(
            name: "TorrServerManager",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)

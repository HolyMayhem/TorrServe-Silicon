// swift-tools-version: 5.9

import Foundation
import PackageDescription

let localTestsPath = "Tests/TorrServerManagerTests"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

var packageTargets: [Target] = [
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

if FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(localTestsPath).path
) {
    packageTargets.append(
        .testTarget(
            name: "TorrServerManagerTests",
            dependencies: ["TorrServerManager"],
            path: localTestsPath
        )
    )
}

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
    targets: packageTargets
)

// swift-tools-version: 5.9

import Foundation
import PackageDescription

let localTestsPath = "Tests/TorrServerManagerTests"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

var packageTargets: [Target] = [
    .executableTarget(
        name: "TorrServerManager",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
            "Telemetry"
        ],
        path: "Sources",
        exclude: ["Telemetry"],
        linkerSettings: [
            .unsafeFlags([
                "-Xlinker", "-rpath",
                "-Xlinker", "@executable_path/../Frameworks"
            ])
        ]
    ),
    .target(name: "Telemetry", path: "Sources/Telemetry"),
    .testTarget(name: "TelemetryTests", dependencies: ["Telemetry"], path: "Tests/TelemetryTests")
]

if FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(localTestsPath).path
) && ProcessInfo.processInfo.environment["TORRSERVE_TELEMETRY_TESTS_ONLY"] != "1" {
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

import AppKit
import Foundation

enum PlayerDetector {
    static let featuredChoices: [ExternalPlayerChoice] = [.iina, .vlc, .infuse]

    static func detectFeaturedPlayers() -> [DetectedPlayer] {
        featuredChoices.map { choice in
            DetectedPlayer(
                choice: choice,
                applicationURL: choice.bundleIdentifier.flatMap {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                }
            )
        }
    }

    static func applicationURL(for choice: ExternalPlayerChoice) -> URL? {
        guard let bundleIdentifier = choice.bundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    }
}

enum ExternalPlayerLauncher {
    static func open(
        _ streamURL: URL,
        using choice: ExternalPlayerChoice,
        customPlayerPath: String
    ) throws {
        if choice == .systemDefault {
            guard NSWorkspace.shared.open(streamURL) else {
                throw AppError("macOS could not open the stream URL.")
            }
            return
        }

        let applicationURL: URL?
        switch choice {
        case .quickTime:
            applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.QuickTimePlayerX"
            )
        case .iina:
            applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.colliderli.iina"
            )
        case .vlc:
            applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "org.videolan.vlc"
            )
        case .infuse:
            applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.firecore.infuse"
            )
        case .custom:
            applicationURL = customPlayerPath.isEmpty
                ? nil
                : URL(fileURLWithPath: customPlayerPath)
        case .systemDefault:
            applicationURL = nil
        }

        guard
            let applicationURL,
            FileManager.default.fileExists(atPath: applicationURL.path)
        else {
            throw AppError("The selected media player is not installed.")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [streamURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("Could not open stream in player: %@", error.localizedDescription)
            }
        }
    }
}

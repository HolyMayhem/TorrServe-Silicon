import Foundation

final class LaunchAtLoginController {
    private let label = "com.holymayhem.torrserver.login"
    private let legacyLabel = "local.codex.torrserver-manager.login"

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    func migrateLegacyAgentIfNeeded() {
        let legacyURL = launchAgentURL(label: legacyLabel)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        do {
            if !isEnabled {
                try installLaunchAgent()
            }
            try FileManager.default.removeItem(at: legacyURL)
        } catch {
            // Keep the old agent intact if migration cannot be completed safely.
        }
    }

    private var plistURL: URL {
        launchAgentURL(label: label)
    }

    private func launchAgentURL(label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private func installLaunchAgent() throws {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            throw AppError("Автозапуск работает только у собранного .app приложения.")
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: plistURL, options: .atomic)
    }
}

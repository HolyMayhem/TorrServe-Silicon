import AppKit

@MainActor
public func runTorrServeApplication() {
    migrateLegacyPreferencesIfNeeded()

    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}

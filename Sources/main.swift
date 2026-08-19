import AppKit

migrateLegacyPreferencesIfNeeded()

let app = NSApplication.shared
let appDelegate = MainActor.assumeIsolated {
    AppDelegate()
}
app.delegate = appDelegate
app.run()

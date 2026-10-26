import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}
let original = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
func makeManifest(build: Int = 42, id: String = "release-42", enabled: Bool = true) throws -> WhatsNewManifest {
    var value = original
    value["build"] = build; value["id"] = id; value["enabled"] = enabled
    return try WhatsNewManifest.load(data: JSONSerialization.data(withJSONObject: value))
}
func rejects(_ value: [String: Any]) -> Bool {
    do { _ = try WhatsNewManifest.load(data: JSONSerialization.data(withJSONObject: value)); return false }
    catch { return true }
}
var suites: [String] = []
func makeDefaults() -> UserDefaults {
    let suite = "TorrServeWhatsNewTests.\(UUID().uuidString)"
    suites.append(suite)
    return UserDefaults(suiteName: suite)!
}
defer { for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) } }
let announcement = try makeManifest()
expect(announcement.content(languageCode: "ru").title == "Что нового", "Russian content")
expect(announcement.content(languageCode: "de") == announcement.content(languageCode: "en"), "English fallback")
var invalid = original; invalid["schemaVersion"] = 2
expect(rejects(invalid), "Reject unknown schema")
invalid = original; invalid["id"] = "bad\nid"
expect(rejects(invalid), "Reject invalid identifier")
invalid = original; invalid["id"] = "id\n"
expect(rejects(invalid), "Reject a trailing newline in the identifier")
invalid = original; invalid["detailsURL"] = "file:///tmp/changelog"
expect(rejects(invalid), "Reject local file links")
invalid = original; invalid["detailsURL"] = "javascript:alert(1)"
expect(rejects(invalid), "Reject executable links")
invalid = original; invalid["build"] = 0
expect(rejects(invalid), "Reject non-positive builds")
invalid = original; invalid["enabled"] = "true"
expect(rejects(invalid), "Reject string flags")
invalid = original; invalid["localizations"] = [:]
expect(rejects(invalid), "Require fallback content")
var translations = original["localizations"] as! [String: Any]
var english = translations["en"] as! [String: Any]
english["features"] = []; translations["en"] = english
invalid = original; invalid["localizations"] = translations
expect(rejects(invalid), "Require at least one feature")
invalid = original; invalid["detailsURL"] = NSNull()
expect(!rejects(invalid), "Details link is optional")

let fresh = WhatsNewHistory(defaults: makeDefaults())
expect(!fresh.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: false), "No announcement on a fresh install")
expect(!fresh.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: false), "No fresh-install announcement on the second launch either")
let defaults = makeDefaults()
let history = WhatsNewHistory(defaults: defaults)
expect(!history.prepareLaunch(currentBuild: 41, manifest: nil, hadPreviousInstallation: false), "Record the baseline without an announcement")
expect(history.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Announce an enabled upgrade")
expect(history.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Keep an unacknowledged announcement after quitting")
history.acknowledge(announcement.id)
expect(!history.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Acknowledgement prevents repeats")
let sameID = try makeManifest(build: 43)
expect(!history.prepareLaunch(currentBuild: 43, manifest: sameID, hadPreviousInstallation: true), "The same ID never repeats on another build")
let disabled = try makeManifest(build: 44, id: "fix", enabled: false)
expect(!history.prepareLaunch(currentBuild: 44, manifest: disabled, hadPreviousInstallation: true), "A fix can suppress the announcement")
let next = try makeManifest(build: 45, id: "new-feature")
expect(history.prepareLaunch(currentBuild: 45, manifest: next, hadPreviousInstallation: true), "A new announcement ID is independent")
let rollback = try makeManifest(build: 43, id: "old-message")
expect(!history.prepareLaunch(currentBuild: 43, manifest: rollback, hadPreviousInstallation: true), "Do not announce downgrades")
let mismatch = WhatsNewHistory(defaults: makeDefaults())
_ = mismatch.prepareLaunch(currentBuild: 41, manifest: nil, hadPreviousInstallation: false)
expect(!mismatch.prepareLaunch(currentBuild: 42, manifest: next, hadPreviousInstallation: true), "Require a matching release build")
expect(mismatch.prepareLaunch(currentBuild: 45, manifest: next, hadPreviousInstallation: true), "Support skipping several versions")
let migrated = WhatsNewHistory(defaults: makeDefaults())
expect(migrated.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Recognize an existing install without a prior tracker")
let missing = WhatsNewHistory(defaults: makeDefaults())
_ = missing.prepareLaunch(currentBuild: 41, manifest: nil, hadPreviousInstallation: false)
expect(!missing.prepareLaunch(currentBuild: 42, manifest: nil, hadPreviousInstallation: true), "A missing resource must not block startup")
let later = try makeManifest(build: 43, id: "later")
expect(missing.prepareLaunch(currentBuild: 43, manifest: later, hadPreviousInstallation: true), "Record builds even when an announcement is absent")
let invalidBuild = WhatsNewHistory(defaults: makeDefaults())
_ = invalidBuild.prepareLaunch(currentBuild: 41, manifest: nil, hadPreviousInstallation: false)
expect(!invalidBuild.prepareLaunch(currentBuild: 0, manifest: announcement, hadPreviousInstallation: true), "Invalid bundle build is ignored")
expect(invalidBuild.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Invalid builds do not corrupt the baseline")
let abandoned = WhatsNewHistory(defaults: makeDefaults())
_ = abandoned.prepareLaunch(currentBuild: 41, manifest: nil, hadPreviousInstallation: false)
_ = abandoned.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true)
let disabledPending = try makeManifest(enabled: false)
expect(!abandoned.prepareLaunch(currentBuild: 42, manifest: disabledPending, hadPreviousInstallation: true), "Disable a queued announcement")
expect(!abandoned.prepareLaunch(currentBuild: 42, manifest: announcement, hadPreviousInstallation: true), "Do not restore an expired pending announcement")

let markerDefaults = makeDefaults()
let markerDomain = suites.last!
markerDefaults.register(defaults: ["AppLanguage": "ru", "SUHasLaunchedBefore": true])
expect(!WhatsNewHistory.hasPreviousInstallation(defaults: markerDefaults, bundleIdentifier: markerDomain), "Registered defaults are not evidence of an old install")
markerDefaults.set("ru", forKey: "AppLanguage")
expect(WhatsNewHistory.hasPreviousInstallation(defaults: markerDefaults, bundleIdentifier: markerDomain), "Persisted preferences recognize existing users")
print("What’s New: \(checks) checks passed")

import Foundation

struct WhatsNewManifest: Decodable, Equatable {
    struct Feature: Decodable, Equatable {
        let symbol: String
        let title: String
        let body: String
    }
    struct Content: Decodable, Equatable {
        let title: String
        let continueTitle: String
        let detailsTitle: String
        let features: [Feature]
    }

    let schemaVersion: Int
    let id: String
    let enabled: Bool
    let build: Int
    let detailsURL: URL?
    let localizations: [String: Content]

    func content(languageCode: String) -> Content {
        // Validation guarantees an English fallback exists.
        localizations[languageCode] ?? localizations["en"]!
    }

    static func load(data: Data) throws -> WhatsNewManifest {
        let manifest = try JSONDecoder().decode(WhatsNewManifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.build > 0,
              manifest.id.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]{0,119}\z"#, options: .regularExpression) != nil,
              manifest.localizations["en"] != nil else {
            throw WhatsNewError.invalidManifest
        }
        if let url = manifest.detailsURL {
            guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
                throw WhatsNewError.invalidManifest
            }
        }
        for content in manifest.localizations.values {
            let labels = [content.title, content.continueTitle, content.detailsTitle]
            guard labels.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 120 }),
                  (1...6).contains(content.features.count),
                  content.features.allSatisfy({ feature in
                      !feature.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && feature.symbol.count <= 100
                          && !feature.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && feature.title.count <= 120
                          && !feature.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && feature.body.count <= 600
                  }) else { throw WhatsNewError.invalidManifest }
        }
        return manifest
    }
}

enum WhatsNewError: LocalizedError {
    case invalidManifest
    var errorDescription: String? { "Invalid WhatsNew.json. Check the announcement fields and schema version." }
}

/// All history stays on this Mac. No networking or update-service dependency.
struct WhatsNewHistory {
    private let defaults: UserDefaults
    private let lastBuildKey = "WhatsNew.LastBuild"
    private let pendingKey = "WhatsNew.PendingID"
    private let seenKey = "WhatsNew.SeenIDs"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func hasPreviousInstallation(defaults: UserDefaults = .standard, bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier,
              let persisted = defaults.persistentDomain(forName: bundleIdentifier) else { return false }
        // Capture before the updater/UI initializes. Registered defaults do not count.
        let markers = ["TorrServerExecutablePath", "AppLanguage", "LibraryDisplayMode", "SULastCheckTime"]
        return markers.contains { persisted[$0] != nil } || persisted["SUHasLaunchedBefore"] as? Bool == true
    }

    func prepareLaunch(currentBuild: Int, manifest: WhatsNewManifest?, hadPreviousInstallation: Bool) -> Bool {
        guard currentBuild > 0 else { return false }
        let previousBuild = defaults.object(forKey: lastBuildKey) as? Int
        let pendingID = defaults.string(forKey: pendingKey)
        let seenIDs = Set(defaults.stringArray(forKey: seenKey) ?? [])
        defaults.set(currentBuild, forKey: lastBuildKey)

        guard let manifest, manifest.enabled, manifest.build == currentBuild,
              !seenIDs.contains(manifest.id) else {
            defaults.removeObject(forKey: pendingKey)
            return false
        }
        let isUpgrade = previousBuild.map { currentBuild > $0 } ?? hadPreviousInstallation
        let isPendingRelaunch = previousBuild == currentBuild && pendingID == manifest.id
        guard isUpgrade || isPendingRelaunch else {
            defaults.removeObject(forKey: pendingKey)
            return false
        }
        defaults.set(manifest.id, forKey: pendingKey)
        return true
    }

    func acknowledge(_ id: String) {
        var seenIDs = Set(defaults.stringArray(forKey: seenKey) ?? [])
        seenIDs.insert(id)
        defaults.set(seenIDs.sorted(), forKey: seenKey)
        if defaults.string(forKey: pendingKey) == id { defaults.removeObject(forKey: pendingKey) }
    }
}

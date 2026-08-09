import Foundation

enum OverviewTranslationMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case original
}

struct TMDBConfiguration: Equatable, Sendable {
    let apiKey: String
    let apiBaseURL: URL

    init(
        apiKey: String,
        apiBaseURL: URL = URL(string: "https://api.themoviedb.org/3")!
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiBaseURL = apiBaseURL
    }
}

struct OMDBConfiguration: Equatable, Sendable {
    let apiKey: String
    let apiBaseURL: URL

    init(
        apiKey: String,
        apiBaseURL: URL = URL(string: "https://www.omdbapi.com/")!
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiBaseURL = apiBaseURL
    }
}

protocol TMDBConfigurationProviding: Sendable {
    func tmdbConfiguration() -> TMDBConfiguration?
}

protocol OMDBConfigurationProviding: Sendable {
    func omdbConfiguration() -> OMDBConfiguration?
}

struct MetadataProviderSettings: Equatable, Sendable {
    var selectedProvider: MetadataProvider
    var tmdbAPIKey: String
    var omdbAPIKey: String
    var overviewTranslationMode: OverviewTranslationMode

    func apiKey(for provider: MetadataProvider) -> String {
        switch provider {
        case .tmdb: return tmdbAPIKey
        case .omdb: return omdbAPIKey
        }
    }

    func isConfigured(_ provider: MetadataProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }
}

final class MetadataSettingsStore: TMDBConfigurationProviding, OMDBConfigurationProviding, @unchecked Sendable {
    static let shared = MetadataSettingsStore()

    private struct Payload: Codable {
        var selectedProvider: MetadataProvider
        var tmdbAPIKey: String
        var omdbAPIKey: String
        var overviewTranslationMode: OverviewTranslationMode?
    }

    private struct LegacyTMDBPayload: Codable {
        let apiKey: String
    }

    private let fileManager: FileManager
    private let fileURL: URL?
    private let legacyTMDBURL: URL?
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        legacyTMDBURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
        self.fileURL = fileURL ?? directory?.appendingPathComponent("metadata.json")
        self.legacyTMDBURL = legacyTMDBURL ?? directory?.appendingPathComponent("tmdb.json")
    }

    var settings: MetadataProviderSettings {
        lock.withLock {
            let payload = loadPayload()
            return MetadataProviderSettings(
                selectedProvider: payload.selectedProvider,
                tmdbAPIKey: payload.tmdbAPIKey,
                omdbAPIKey: payload.omdbAPIKey,
                overviewTranslationMode: payload.overviewTranslationMode ?? .automatic
            )
        }
    }

    func isConfigured(_ provider: MetadataProvider) -> Bool {
        settings.isConfigured(provider)
    }

    func save(selectedProvider: MetadataProvider) throws {
        try lock.withLock {
            var payload = loadPayload()
            payload.selectedProvider = selectedProvider
            try persist(payload)
        }
    }

    func save(apiKey: String, for provider: MetadataProvider) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try lock.withLock {
            var payload = loadPayload()
            switch provider {
            case .tmdb: payload.tmdbAPIKey = value
            case .omdb: payload.omdbAPIKey = value
            }
            try persist(payload)
        }
    }

    func save(overviewTranslationMode: OverviewTranslationMode) throws {
        try lock.withLock {
            var payload = loadPayload()
            payload.overviewTranslationMode = overviewTranslationMode
            try persist(payload)
        }
    }

    func tmdbConfiguration() -> TMDBConfiguration? {
        let value = settings.tmdbAPIKey
        guard !value.isEmpty else { return nil }
        return TMDBConfiguration(apiKey: value)
    }

    func omdbConfiguration() -> OMDBConfiguration? {
        let value = settings.omdbAPIKey
        guard !value.isEmpty else { return nil }
        return OMDBConfiguration(apiKey: value)
    }

    private func loadPayload() -> Payload {
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return payload
        }

        let legacyKey: String
        if let legacyTMDBURL,
           let data = try? Data(contentsOf: legacyTMDBURL),
           let payload = try? JSONDecoder().decode(LegacyTMDBPayload.self, from: data) {
            legacyKey = payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            legacyKey = ""
        }
        return Payload(
            selectedProvider: .tmdb,
            tmdbAPIKey: legacyKey,
            omdbAPIKey: "",
            overviewTranslationMode: .automatic
        )
    }

    private func persist(_ payload: Payload) throws {
        guard let fileURL else { throw MetadataSettingsError.storageUnavailable }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

enum MetadataSettingsError: LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        "Could not access the TorrServer settings folder."
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

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

struct KinopoiskConfiguration: Equatable, Sendable {
    let apiKey: String
    let apiBaseURL: URL

    init(
        apiKey: String,
        apiBaseURL: URL = URL(string: "https://kinopoiskapiunofficial.tech")!
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

protocol KinopoiskConfigurationProviding: Sendable {
    func kinopoiskConfiguration() -> KinopoiskConfiguration?
}

struct MetadataProviderSettings: Equatable, Sendable {
    static let defaultCombinedOrder: [MetadataProvider] = [.omdb, .kinopoisk, .tmdb]

    var selectedSource: MetadataSourceMode
    var apiKeyMode: MetadataAPIKeyMode
    var combinedOrder: [MetadataProvider]
    var tmdbAPIKey: String
    var omdbAPIKey: String
    var kinopoiskAPIKey: String
    var overviewTranslationMode: OverviewTranslationMode

    func apiKey(for provider: MetadataProvider) -> String {
        switch provider {
        case .tmdb: return tmdbAPIKey
        case .omdb: return omdbAPIKey
        case .kinopoisk: return kinopoiskAPIKey
        }
    }

    var resolutionOrder: [MetadataProvider] {
        selectedSource.singleProvider.map { [$0] }
            ?? Self.normalizedOrder(combinedOrder)
    }

    static func normalizedOrder(_ providers: [MetadataProvider]) -> [MetadataProvider] {
        var seen = Set<MetadataProvider>()
        let unique = providers.filter { seen.insert($0).inserted }
        return unique + defaultCombinedOrder.filter { !seen.contains($0) }
    }
}

struct BuiltInMetadataAPIKeys: Equatable, Sendable {
    let tmdb: String
    let omdb: String
    let kinopoisk: String

    static let empty = BuiltInMetadataAPIKeys(tmdb: "", omdb: "", kinopoisk: "")

    func apiKey(for provider: MetadataProvider) -> String {
        switch provider {
        case .tmdb: return tmdb
        case .omdb: return omdb
        case .kinopoisk: return kinopoisk
        }
    }
}

final class MetadataSettingsStore: TMDBConfigurationProviding, OMDBConfigurationProviding, KinopoiskConfigurationProviding, @unchecked Sendable {
    static let shared = MetadataSettingsStore()

    private struct Payload: Codable {
        var selectedProvider: MetadataProvider?
        var selectedSource: MetadataSourceMode?
        var apiKeyMode: MetadataAPIKeyMode?
        var combinedOrder: [MetadataProvider]?
        var tmdbAPIKey: String
        var omdbAPIKey: String
        var kinopoiskAPIKey: String?
        var overviewTranslationMode: OverviewTranslationMode?
    }

    private struct LegacyTMDBPayload: Codable {
        let apiKey: String
    }

    private let fileManager: FileManager
    private let fileURL: URL?
    private let legacyTMDBURL: URL?
    private let builtInAPIKeys: BuiltInMetadataAPIKeys
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        legacyTMDBURL: URL? = nil,
        builtInAPIKeys: BuiltInMetadataAPIKeys? = nil
    ) {
        self.fileManager = fileManager
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
        self.fileURL = fileURL ?? directory?.appendingPathComponent("metadata.json")
        self.legacyTMDBURL = legacyTMDBURL ?? directory?.appendingPathComponent("tmdb.json")
        self.builtInAPIKeys = builtInAPIKeys ?? Self.loadBuiltInAPIKeys()
    }

    var settings: MetadataProviderSettings {
        lock.withLock {
            let payload = loadPayload()
            return MetadataProviderSettings(
                selectedSource: payload.selectedSource
                    ?? payload.selectedProvider.map(MetadataSourceMode.init(provider:))
                    ?? .tmdb,
                apiKeyMode: payload.apiKeyMode ?? .builtIn,
                combinedOrder: MetadataProviderSettings.normalizedOrder(
                    payload.combinedOrder ?? MetadataProviderSettings.defaultCombinedOrder
                ),
                tmdbAPIKey: payload.tmdbAPIKey,
                omdbAPIKey: payload.omdbAPIKey,
                kinopoiskAPIKey: payload.kinopoiskAPIKey ?? "",
                overviewTranslationMode: payload.overviewTranslationMode ?? .automatic
            )
        }
    }

    func isConfigured(_ provider: MetadataProvider) -> Bool {
        !effectiveAPIKey(for: provider).isEmpty
    }

    func save(selectedSource: MetadataSourceMode) throws {
        try lock.withLock {
            var payload = loadPayload()
            payload.selectedSource = selectedSource
            try persist(payload)
        }
    }

    func save(apiKeyMode: MetadataAPIKeyMode) throws {
        try lock.withLock {
            var payload = loadPayload()
            payload.apiKeyMode = apiKeyMode
            try persist(payload)
        }
    }

    func save(combinedOrder: [MetadataProvider]) throws {
        try lock.withLock {
            var payload = loadPayload()
            payload.combinedOrder = MetadataProviderSettings.normalizedOrder(combinedOrder)
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
            case .kinopoisk: payload.kinopoiskAPIKey = value
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
        let value = effectiveAPIKey(for: .tmdb)
        guard !value.isEmpty else { return nil }
        return TMDBConfiguration(apiKey: value)
    }

    func omdbConfiguration() -> OMDBConfiguration? {
        let value = effectiveAPIKey(for: .omdb)
        guard !value.isEmpty else { return nil }
        return OMDBConfiguration(apiKey: value)
    }

    func kinopoiskConfiguration() -> KinopoiskConfiguration? {
        let value = effectiveAPIKey(for: .kinopoisk)
        guard !value.isEmpty else { return nil }
        return KinopoiskConfiguration(apiKey: value)
    }

    private func effectiveAPIKey(for provider: MetadataProvider) -> String {
        let currentSettings = settings
        let value = currentSettings.apiKeyMode == .builtIn
            ? builtInAPIKeys.apiKey(for: provider)
            : currentSettings.apiKey(for: provider)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
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
            selectedProvider: nil,
            selectedSource: .tmdb,
            apiKeyMode: .builtIn,
            combinedOrder: MetadataProviderSettings.defaultCombinedOrder,
            tmdbAPIKey: legacyKey,
            omdbAPIKey: "",
            kinopoiskAPIKey: "",
            overviewTranslationMode: .automatic
        )
    }

    private static func loadBuiltInAPIKeys(bundle: Bundle = .main) -> BuiltInMetadataAPIKeys {
        guard let values = bundle.object(
            forInfoDictionaryKey: "TorrServeMetadataAPIKeys"
        ) as? [String: String] else {
            return .empty
        }
        return BuiltInMetadataAPIKeys(
            tmdb: values["TMDB"] ?? "",
            omdb: values["OMDB"] ?? "",
            kinopoisk: values["Kinopoisk"] ?? ""
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

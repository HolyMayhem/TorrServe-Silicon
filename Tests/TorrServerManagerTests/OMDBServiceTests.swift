import Foundation
import XCTest
@testable import TorrServerKit

final class OMDBServiceTests: XCTestCase {
    func testSearchNormalizesSeriesResult() async throws {
        let service = makeService(response: """
        {
          "Search": [{
            "Title": "The Last of Us",
            "Year": "2023–",
            "imdbID": "tt3581920",
            "Type": "series",
            "Poster": "https://example.com/poster.jpg"
          }],
          "totalResults": "1",
          "Response": "True"
        }
        """)

        let results = try await service.search(
            title: "The Last of Us",
            year: 2023,
            kind: .tv,
            language: "ru-RU"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "tt3581920")
        XCTAssertEqual(results.first?.provider, .omdb)
        XCTAssertEqual(results.first?.kind, .tv)
        XCTAssertEqual(results.first?.releaseYear, 2023)
        XCTAssertEqual(results.first?.posterURL?.absoluteString, "https://example.com/poster.jpg")
    }

    func testDetailsNormalizesOMDBFields() async throws {
        let service = makeService(response: """
        {
          "Title": "Dune: Part Two",
          "Year": "2024",
          "Released": "01 Mar 2024",
          "Runtime": "166 min",
          "Genre": "Action, Adventure, Drama",
          "Plot": "Paul unites with Chani and the Fremen.",
          "Poster": "https://example.com/dune.jpg",
          "imdbRating": "8.5",
          "imdbID": "tt15239678",
          "Type": "movie",
          "Response": "True"
        }
        """)

        let metadata = try await service.details(
            id: "tt15239678",
            kind: .movie,
            language: "en-US"
        )

        XCTAssertEqual(metadata.provider, .omdb)
        XCTAssertEqual(metadata.localizedTitle, "Dune: Part Two")
        XCTAssertEqual(metadata.runtimeMinutes, 166)
        XCTAssertEqual(metadata.genres, ["Action", "Adventure", "Drama"])
        XCTAssertEqual(metadata.rating, 8.5)
        XCTAssertNil(metadata.backdropURL)
    }

    func testMovieNotFoundReturnsEmptySearchResults() async throws {
        let service = makeService(response: """
        { "Response": "False", "Error": "Movie not found!" }
        """)

        let results = try await service.search(
            title: "Missing",
            year: nil,
            kind: .movie,
            language: "en-US"
        )

        XCTAssertTrue(results.isEmpty)
    }

    private func makeService(response: String) -> OMDBService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OMDBURLProtocol.self]
        OMDBURLProtocol.responseData = Data(response.utf8)
        return OMDBService(
            configurationProvider: OMDBConfigurationStub(),
            session: URLSession(configuration: configuration)
        )
    }
}

final class MetadataSettingsStoreTests: XCTestCase {
    func testPersistsSelectedProviderAndSeparateKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("metadata.json")
        let store = MetadataSettingsStore(
            fileURL: fileURL,
            legacyTMDBURL: directory.appendingPathComponent("legacy.json"),
            builtInAPIKeys: .empty
        )

        try store.save(apiKey: "tmdb-key", for: .tmdb)
        try store.save(apiKey: "omdb-key", for: .omdb)
        try store.save(apiKey: "kinopoisk-key", for: .kinopoisk)
        try store.save(selectedSource: .combined)
        try store.save(apiKeyMode: .custom)
        try store.save(combinedOrder: [.kinopoisk, .tmdb, .omdb])
        try store.save(overviewTranslationMode: .original)

        let reloaded = MetadataSettingsStore(
            fileURL: fileURL,
            legacyTMDBURL: directory.appendingPathComponent("legacy.json"),
            builtInAPIKeys: .empty
        ).settings
        XCTAssertEqual(reloaded.selectedSource, .combined)
        XCTAssertEqual(reloaded.apiKeyMode, .custom)
        XCTAssertEqual(reloaded.combinedOrder, [.kinopoisk, .tmdb, .omdb])
        XCTAssertEqual(reloaded.tmdbAPIKey, "tmdb-key")
        XCTAssertEqual(reloaded.omdbAPIKey, "omdb-key")
        XCTAssertEqual(reloaded.kinopoiskAPIKey, "kinopoisk-key")
        XCTAssertEqual(reloaded.overviewTranslationMode, .original)
    }

    func testDefaultsTranslationToAutomaticForExistingSettingsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("metadata.json")
        try Data(#"{"selectedProvider":"omdb","tmdbAPIKey":"","omdbAPIKey":"key"}"#.utf8)
            .write(to: fileURL)

        let settings = MetadataSettingsStore(
            fileURL: fileURL,
            legacyTMDBURL: directory.appendingPathComponent("legacy.json"),
            builtInAPIKeys: .empty
        ).settings

        XCTAssertEqual(settings.overviewTranslationMode, .automatic)
        XCTAssertEqual(settings.kinopoiskAPIKey, "")
        XCTAssertEqual(settings.selectedSource, .omdb)
        XCTAssertEqual(settings.apiKeyMode, .builtIn)
        XCTAssertEqual(settings.combinedOrder, [.omdb, .kinopoisk, .tmdb])
    }

    func testBuiltInAndCustomKeyModesUseDifferentKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetadataSettingsStore(
            fileURL: directory.appendingPathComponent("metadata.json"),
            legacyTMDBURL: directory.appendingPathComponent("legacy.json"),
            builtInAPIKeys: BuiltInMetadataAPIKeys(
                tmdb: "built-in-tmdb",
                omdb: "built-in-omdb",
                kinopoisk: "built-in-kinopoisk"
            )
        )

        XCTAssertEqual(store.tmdbConfiguration()?.apiKey, "built-in-tmdb")
        XCTAssertEqual(store.omdbConfiguration()?.apiKey, "built-in-omdb")
        XCTAssertEqual(store.kinopoiskConfiguration()?.apiKey, "built-in-kinopoisk")

        try store.save(apiKey: "custom-omdb", for: .omdb)
        try store.save(apiKeyMode: .custom)

        XCTAssertEqual(store.omdbConfiguration()?.apiKey, "custom-omdb")
        XCTAssertNil(store.tmdbConfiguration())
    }
}

final class OverviewTranslationTests: XCTestCase {
    func testTranslationPolicyOnlyUsesEnglishOMDBOverviewInRussianAutomaticMode() {
        XCTAssertTrue(OverviewTranslationPolicy.shouldTranslate(
            "A criminal returns to the city for one final job.",
            provider: .omdb,
            language: .russian,
            mode: .automatic
        ))
        XCTAssertFalse(OverviewTranslationPolicy.shouldTranslate(
            "Преступник возвращается в город.",
            provider: .omdb,
            language: .russian,
            mode: .automatic
        ))
        XCTAssertFalse(OverviewTranslationPolicy.shouldTranslate(
            "A criminal returns to the city.",
            provider: .tmdb,
            language: .russian,
            mode: .automatic
        ))
        XCTAssertFalse(OverviewTranslationPolicy.shouldTranslate(
            "A criminal returns to the city.",
            provider: .omdb,
            language: .russian,
            mode: .original
        ))
    }

    func testTranslationCachePersistsByMediaAndSourceText() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("translations.json")
        let source = "An English overview."
        let cache = OverviewTranslationCache(fileURL: fileURL)

        await cache.save(
            "Описание на русском.",
            provider: .omdb,
            mediaID: "tt123",
            sourceText: source,
            targetLanguage: "ru"
        )

        let reloaded = OverviewTranslationCache(fileURL: fileURL)
        let value = await reloaded.value(
            provider: .omdb,
            mediaID: "tt123",
            sourceText: source,
            targetLanguage: "ru"
        )
        XCTAssertEqual(value, "Описание на русском.")
    }
}

private struct OMDBConfigurationStub: OMDBConfigurationProviding {
    func omdbConfiguration() -> OMDBConfiguration? {
        OMDBConfiguration(apiKey: "test-key")
    }
}

private final class OMDBURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

import Foundation
import XCTest
@testable import TorrServerKit

final class LibraryMetadataStoreTests: XCTestCase {
    func testTrackerMetadataIsNotExposedAsLibraryMetadata() {
        let suiteName = "LibraryMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryMetadataStore(defaults: defaults)

        store.save(
            LibraryMetadata(
                title: "Release title",
                posterURL: "https://tracker.example/poster.jpg",
                summary: "Tracker description",
                source: "Rutor"
            ),
            for: "tracker-hash"
        )

        XCTAssertNil(store.metadata(for: "tracker-hash"))
    }

    func testSupportedProviderMetadataRemainsAvailable() {
        let suiteName = "LibraryMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryMetadataStore(defaults: defaults)

        store.save(
            LibraryMetadata(
                title: "Thursday",
                posterURL: "https://metadata.example/poster.jpg",
                summary: "Overview",
                source: "OMDb",
                metadataProvider: .omdb,
                metadataProviderID: "tt0124901"
            ),
            for: "metadata-hash"
        )

        XCTAssertEqual(store.metadata(for: "metadata-hash")?.metadataProvider, .omdb)
    }

    func testRemoveAllClearsPersistedProviderMetadata() {
        let suiteName = "LibraryMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryMetadataStore(defaults: defaults)

        store.save(
            LibraryMetadata(
                title: "The Matrix",
                posterURL: "https://metadata.example/poster.jpg",
                summary: "Overview",
                source: "КиноПоиск",
                metadataProvider: .kinopoisk,
                metadataProviderID: "301"
            ),
            for: "matrix-hash"
        )

        store.removeAll()

        XCTAssertTrue(store.allMetadata().isEmpty)
    }

    @MainActor
    func testConfigurationChangeImmediatelyRemovesMetadataFromPreviousProvider() throws {
        let suiteName = "LibraryMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryMetadataStore(defaults: defaults)
        store.save(
            LibraryMetadata(
                title: "Матрица",
                posterURL: "https://metadata.example/kinopoisk.jpg",
                summary: "Описание",
                source: "КиноПоиск",
                metadataProvider: .kinopoisk,
                metadataProviderID: "301"
            ),
            for: "matrix-hash"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = MetadataSettingsStore(
            fileURL: directory.appendingPathComponent("metadata.json"),
            legacyTMDBURL: directory.appendingPathComponent("legacy.json"),
            builtInAPIKeys: .empty
        )
        try settings.save(selectedSource: .omdb)
        let model = LibraryViewModel(
            metadataStore: store,
            metadataSettings: settings
        )
        XCTAssertEqual(
            model.metadataByHash["matrix-hash"]?.metadataProvider,
            .kinopoisk
        )

        model.metadataConfigurationChanged()

        XCTAssertTrue(model.metadataByHash.isEmpty)
        XCTAssertTrue(store.allMetadata().isEmpty)
    }
}

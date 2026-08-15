import Foundation
import XCTest
@testable import TorrServerManager

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
}

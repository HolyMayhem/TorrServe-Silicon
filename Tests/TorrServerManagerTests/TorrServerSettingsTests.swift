import Foundation
import XCTest
@testable import TorrServerManager

final class TorrServerSettingsTests: XCTestCase {
    func testParsesEditableCacheSettings() throws {
        let data = try JSONSerialization.data(withJSONObject: settingsObject())
        let settings = try TorrServerStorageSettings(data: data)

        XCTAssertEqual(settings.cacheSize, 128 * 1_048_576)
        XCTAssertEqual(settings.readerReadAhead, 92)
        XCTAssertEqual(settings.preloadCache, 55)
        XCTAssertTrue(settings.useDisk)
        XCTAssertEqual(settings.torrentsSavePath, "/Volumes/Cache")
        XCTAssertTrue(settings.removeCacheOnDrop)
        XCTAssertEqual(settings.draft.cacheSizeMB, 128)
    }

    func testUpdatePayloadPreservesUnrelatedServerSettings() throws {
        let data = try JSONSerialization.data(withJSONObject: settingsObject())
        let settings = try TorrServerStorageSettings(data: data)
        let draft = TorrServerSettingsDraft(
            cacheSizeMB: 256,
            readerReadAhead: 80,
            preloadCache: 25,
            useDisk: false,
            torrentsSavePath: "",
            removeCacheOnDrop: false
        )

        let payload = try settings.payload(applying: draft)

        XCTAssertEqual((payload["CacheSize"] as? NSNumber)?.int64Value, 256 * 1_048_576)
        XCTAssertEqual((payload["ReaderReadAHead"] as? NSNumber)?.intValue, 80)
        XCTAssertEqual((payload["PreloadCache"] as? NSNumber)?.intValue, 25)
        XCTAssertEqual((payload["UseDisk"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual(payload["TorrentsSavePath"] as? String, "")
        XCTAssertEqual((payload["RemoveCacheOnDrop"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((payload["EnableDHT"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((payload["ConnectionsLimit"] as? NSNumber)?.intValue, 42)
    }

    private func settingsObject() -> [String: Any] {
        [
            "CacheSize": 128 * 1_048_576,
            "ReaderReadAHead": 92,
            "PreloadCache": 55,
            "UseDisk": true,
            "TorrentsSavePath": "/Volumes/Cache",
            "RemoveCacheOnDrop": true,
            "EnableDHT": true,
            "ConnectionsLimit": 42
        ]
    }
}

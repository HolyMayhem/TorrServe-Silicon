import Foundation
import XCTest
@testable import TorrServerManager

final class TorrServerModelsTests: XCTestCase {
    func testDecodesNativeSnakeCaseResponse() throws {
        let torrent = try decode([
            "title": "Example",
            "hash": "abc",
            "loaded_size": 25,
            "torrent_size": 100,
            "connected_seeders": 4,
            "file_stats": [["id": 2, "path": "Video.mkv", "length": 100]]
        ])

        XCTAssertEqual(torrent.displayTitle, "Example")
        XCTAssertEqual(torrent.hash, "abc")
        XCTAssertEqual(torrent.menuBufferProgress, 0.25)
        XCTAssertEqual(torrent.connectedSeeders, 4)
        XCTAssertEqual(torrent.allFiles.first?.displayName, "Video.mkv")
    }

    func testDecodesLegacyUpperCamelCaseResponse() throws {
        let torrent = try decode([
            "Title": "Legacy",
            "Hash": "def",
            "LoadedSize": 50,
            "TorrentSize": 200,
            "ConnectedSeeders": 7,
            "FileStats": [["Id": 3, "Path": "Legacy.mp4", "Length": 200]]
        ])

        XCTAssertEqual(torrent.displayTitle, "Legacy")
        XCTAssertEqual(torrent.hash, "def")
        XCTAssertEqual(torrent.menuBufferProgress, 0.25)
        XCTAssertEqual(torrent.connectedSeeders, 7)
        XCTAssertEqual(torrent.allFiles.first?.displayName, "Legacy.mp4")
    }

    private func decode(_ object: [String: Any]) throws -> NativeTorrent {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(NativeTorrent.self, from: data)
    }
}

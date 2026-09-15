import Foundation
import XCTest
@testable import TorrServerManager

final class OfflineDownloadQueueStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: OfflineDownloadQueueStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-queue-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        store = OfflineDownloadQueueStore(
            fileURL: temporaryDirectory.appendingPathComponent("queue.json")
        )
    }

    override func tearDownWithError() throws {
        store = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRoundTripsQueueInOrder() throws {
        let first = makeRequest(name: "first.mkv", index: 1)
        let second = makeRequest(name: "second.mkv", index: 2)

        try store.save([first, second])

        XCTAssertEqual(try store.load(), [first, second])
    }

    func testSavingEmptyQueueRemovesStore() throws {
        try store.save([makeRequest(name: "movie.mkv", index: 1)])

        try store.save([])

        XCTAssertEqual(try store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL!.path))
    }

    private func makeRequest(name: String, index: Int) -> OfflineDownloadRequest {
        OfflineDownloadRequest(
            sourceURL: URL(string: "http://127.0.0.1:8090/stream/\(index)")!,
            destinationURL: temporaryDirectory.appendingPathComponent(name),
            expectedLength: Int64(index * 1_024)
        )
    }
}

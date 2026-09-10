import Foundation
import XCTest
@testable import TorrServerManager

final class OfflineDownloadHistoryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: OfflineDownloadHistoryStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-history-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        store = OfflineDownloadHistoryStore(
            fileURL: temporaryDirectory.appendingPathComponent("completed.json")
        )
    }

    override func tearDownWithError() throws {
        store = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRoundTripsCompletedDownloads() throws {
        let record = makeRecord()

        try store.save([record])

        XCTAssertEqual(try store.load(), [record])
    }

    func testRejectsUnsupportedSchema() throws {
        try store.save([makeRecord()])
        let fileURL = try XCTUnwrap(store.fileURL)
        let data = try Data(contentsOf: fileURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(
            to: fileURL,
            options: .atomic
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(
                error as? OfflineDownloadCheckpointStoreError,
                .unsupportedSchema(99)
            )
        }
    }

    private func makeRecord() -> OfflineDownloadRecord {
        OfflineDownloadRecord(
            sourceURL: URL(string: "http://127.0.0.1:8090/stream/movie.mkv")!,
            destinationURL: temporaryDirectory.appendingPathComponent("movie.mkv"),
            expectedLength: 16_384,
            completedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
    }
}

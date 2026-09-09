import Foundation
import XCTest
@testable import TorrServerManager

final class OfflineDownloadCheckpointStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: OfflineDownloadCheckpointStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-checkpoint-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        store = OfflineDownloadCheckpointStore(
            fileURL: temporaryDirectory.appendingPathComponent("checkpoint.json")
        )
    }

    override func tearDownWithError() throws {
        store = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRoundTripsCheckpoint() throws {
        let checkpoint = makeCheckpoint(bytesWritten: 4_096)

        try store.save(checkpoint)

        XCTAssertEqual(try store.load(), checkpoint)
    }

    func testSaveAtomicallyReplacesPreviousCheckpoint() throws {
        try store.save(makeCheckpoint(bytesWritten: 1_024))
        let replacement = makeCheckpoint(bytesWritten: 8_192)

        try store.save(replacement)

        XCTAssertEqual(try store.load(), replacement)
    }

    func testClearRemovesSavedCheckpoint() throws {
        try store.save(makeCheckpoint(bytesWritten: 2_048))

        try store.clear()

        XCTAssertNil(try store.load())
    }

    func testRejectsUnsupportedSchema() throws {
        try store.save(makeCheckpoint(bytesWritten: 2_048))
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

    private func makeCheckpoint(bytesWritten: Int64) -> OfflineDownloadCheckpoint {
        let destination = temporaryDirectory.appendingPathComponent("movie.mkv")
        let request = OfflineDownloadRequest(
            sourceURL: URL(string: "http://127.0.0.1:8090/stream/movie.mkv")!,
            destinationURL: destination,
            expectedLength: 16_384
        )
        return OfflineDownloadCheckpoint(
            request: request,
            streamIdentity: OfflineDownloadStreamIdentity(
                contentLength: request.expectedLength,
                entityTag: #""fixture/movie.mkv""#
            ),
            bytesWritten: bytesWritten
        )
    }
}

import Combine
import Foundation
import XCTest
@testable import TorrServerManager

@MainActor
final class OfflineDownloadManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-download-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        cancellables = []
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        cancellables = []
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testCompletesDownloadThroughPartialFile() async throws {
        let payload = Data((0..<131_072).map { UInt8($0 % 251) })
        StubURLProtocol.configure(.init(data: payload, chunkSize: 8_192))
        let destination = temporaryDirectory.appendingPathComponent("movie.mkv")
        let manager = makeManager()
        var observedProgress: [Int64] = []
        manager.$state.sink { state in
            if case .downloading(let progress) = state {
                observedProgress.append(progress.bytesWritten)
            }
        }.store(in: &cancellables)

        try manager.start(makeRequest(destination: destination, length: Int64(payload.count)))
        let state = try await waitForTerminalState(manager)

        XCTAssertEqual(state, .completed(destination))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathExtension("torrserve-part").path
        ))
        XCTAssertTrue(observedProgress.contains(where: { $0 > 0 }))
    }

    func testCancellationRemovesPartialFile() async throws {
        let payload = Data(repeating: 0xA5, count: 1_048_576)
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.005
        ))
        let destination = temporaryDirectory.appendingPathComponent("cancelled.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let manager = makeManager()

        try manager.start(request)
        _ = try await waitForState(manager) { state in
            if case .downloading(let progress) = state {
                return progress.bytesWritten > 0
            }
            return false
        }
        manager.cancel()
        let state = try await waitForTerminalState(manager)

        XCTAssertEqual(state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))
    }

    func testRejectsResponseWithWrongContentLength() async throws {
        let payload = Data(repeating: 0x2A, count: 128)
        StubURLProtocol.configure(.init(
            data: payload,
            advertisedLength: 127,
            chunkSize: 128
        ))
        let destination = temporaryDirectory.appendingPathComponent("wrong-size.mkv")
        let request = makeRequest(destination: destination, length: 128)
        let manager = makeManager()

        try manager.start(request)
        let state = try await waitForTerminalState(manager)

        XCTAssertEqual(
            state,
            .failed(
                .contract(.invalidContentLength(expected: 128, actual: "127")),
                checkpoint: nil
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))
    }

    func testInterruptedTransferKeepsNonEmptyPartialFile() async throws {
        let payload = Data(repeating: 0x7C, count: 4_096)
        StubURLProtocol.configure(.init(
            data: payload,
            advertisedLength: 8_192,
            chunkSize: 1_024
        ))
        let destination = temporaryDirectory.appendingPathComponent("interrupted.mkv")
        let request = makeRequest(destination: destination, length: 8_192)
        let manager = makeManager()

        try manager.start(request)
        let state = try await waitForTerminalState(manager)

        guard case .failed(_, let checkpoint) = state else {
            return XCTFail("Expected a failed state, got \(state).")
        }
        XCTAssertEqual(checkpoint?.request.partialFileURL, request.partialFileURL)
        XCTAssertEqual(checkpoint?.bytesWritten, Int64(payload.count))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: request.partialFileURL.path
            )[.size] as? NSNumber,
            NSNumber(value: payload.count)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRefusesToOverwriteExistingDestination() throws {
        let destination = temporaryDirectory.appendingPathComponent("existing.mkv")
        try Data([1, 2, 3]).write(to: destination)
        let manager = makeManager()

        XCTAssertThrowsError(
            try manager.start(makeRequest(destination: destination, length: 3))
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadStartError,
                .destinationAlreadyExists(destination)
            )
        }
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
    }

    func testRefusesToOverwriteExistingPartialFile() throws {
        let destination = temporaryDirectory.appendingPathComponent("partial.mkv")
        let request = makeRequest(destination: destination, length: 3)
        try Data([4, 5]).write(to: request.partialFileURL)
        let manager = makeManager()

        XCTAssertThrowsError(try manager.start(request)) { error in
            XCTAssertEqual(
                error as? OfflineDownloadStartError,
                .partialFileAlreadyExists(request.partialFileURL)
            )
        }
        XCTAssertEqual(try Data(contentsOf: request.partialFileURL), Data([4, 5]))
    }

    func testAllowsOnlyOneActiveDownload() async throws {
        let payload = Data(repeating: 0x33, count: 1_048_576)
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.005
        ))
        let firstRequest = makeRequest(
            destination: temporaryDirectory.appendingPathComponent("first.mkv"),
            length: Int64(payload.count)
        )
        let secondRequest = makeRequest(
            destination: temporaryDirectory.appendingPathComponent("second.mkv"),
            length: Int64(payload.count)
        )
        let manager = makeManager()

        try manager.start(firstRequest)
        _ = try await waitForState(manager) { $0.isActive }
        XCTAssertThrowsError(try manager.start(secondRequest)) { error in
            XCTAssertEqual(
                error as? OfflineDownloadStartError,
                .anotherDownloadIsActive
            )
        }

        manager.cancel()
        let terminalState = try await waitForTerminalState(manager)
        XCTAssertEqual(terminalState, .cancelled)
    }

    func testPausesAndResumesWithRangeAndIfRange() async throws {
        let payload = Data((0..<1_048_576).map { UInt8($0 % 239) })
        let entityTag = #""fixture/resumable-movie.mkv""#
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.002,
            entityTag: entityTag
        ))
        let destination = temporaryDirectory.appendingPathComponent("resumed.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let manager = makeManager()

        try manager.start(request)
        _ = try await waitForState(manager) { state in
            if case .downloading(let progress) = state {
                return progress.bytesWritten > 0
            }
            return false
        }
        manager.pause()

        let pausedState = try await waitForState(manager) { state in
            if case .paused = state { return true }
            return false
        }
        guard case .paused(let checkpoint) = pausedState else {
            return XCTFail("Expected a paused state, got \(pausedState).")
        }
        XCTAssertGreaterThan(checkpoint.bytesWritten, 0)
        XCTAssertLessThan(checkpoint.bytesWritten, request.expectedLength)
        XCTAssertEqual(
            try partialFileSize(at: request.partialFileURL),
            checkpoint.bytesWritten
        )

        try manager.resume()
        let completedState = try await waitForTerminalState(manager, timeout: 5)

        XCTAssertEqual(completedState, .completed(destination))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))

        let resumedRequest = try XCTUnwrap(
            StubURLProtocol.requestsSnapshot().first { request in
                request.value(forHTTPHeaderField: "Range")
                    == "bytes=\(checkpoint.bytesWritten)-"
            }
        )
        XCTAssertEqual(
            resumedRequest.value(forHTTPHeaderField: "If-Range"),
            entityTag
        )
    }

    func testResumeRejectsFullResponseWithoutAppending() async throws {
        let payload = Data(repeating: 0x6D, count: 1_048_576)
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.002
        ))
        let destination = temporaryDirectory.appendingPathComponent("ignored-range.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let manager = makeManager()

        try manager.start(request)
        _ = try await waitForState(manager) { state in
            if case .downloading(let progress) = state {
                return progress.bytesWritten > 0
            }
            return false
        }
        manager.pause()
        let pausedState = try await waitForState(manager) { state in
            if case .paused = state { return true }
            return false
        }
        guard case .paused(let checkpoint) = pausedState else {
            return XCTFail("Expected a paused state, got \(pausedState).")
        }
        let sizeBeforeResume = try partialFileSize(at: request.partialFileURL)

        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: payload.count,
            honorsRanges: false
        ))
        try manager.resume()
        let failedState = try await waitForTerminalState(manager)

        XCTAssertEqual(
            failedState,
            .failed(.contract(.serverIgnoredRange), checkpoint: checkpoint)
        )
        XCTAssertEqual(
            try partialFileSize(at: request.partialFileURL),
            sizeBeforeResume
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancellingPausedDownloadRemovesPartialFile() async throws {
        let payload = Data(repeating: 0x4E, count: 1_048_576)
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.002
        ))
        let destination = temporaryDirectory.appendingPathComponent("paused-cancel.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let manager = makeManager()

        try manager.start(request)
        _ = try await waitForState(manager) { state in
            if case .downloading(let progress) = state {
                return progress.bytesWritten > 0
            }
            return false
        }
        manager.pause()
        _ = try await waitForState(manager) { state in
            if case .paused = state { return true }
            return false
        }

        manager.cancel()

        XCTAssertEqual(manager.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRestoresPausedDownloadAndResumesAfterManagerRecreation() async throws {
        let payload = Data((0..<1_048_576).map { UInt8($0 % 227) })
        StubURLProtocol.configure(.init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.002
        ))
        let destination = temporaryDirectory.appendingPathComponent("restored.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let checkpointStore = makeCheckpointStore()
        let firstManager = makeManager(checkpointStore: checkpointStore)

        try firstManager.start(request)
        _ = try await waitForState(firstManager) { state in
            if case .downloading(let progress) = state {
                return progress.bytesWritten > 0
            }
            return false
        }
        firstManager.pause()
        let pausedState = try await waitForState(firstManager) { state in
            if case .paused = state { return true }
            return false
        }
        guard case .paused(let pausedCheckpoint) = pausedState else {
            return XCTFail("Expected a paused state, got \(pausedState).")
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try XCTUnwrap(checkpointStore.fileURL).path
        ))

        let restoredManager = makeManager(checkpointStore: checkpointStore)

        XCTAssertEqual(restoredManager.state, .paused(pausedCheckpoint))
        try restoredManager.resume()
        let completedState = try await waitForTerminalState(restoredManager, timeout: 5)

        XCTAssertEqual(completedState, .completed(destination))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertNil(try checkpointStore.load())
    }

    func testRestorationReconcilesCheckpointWithActualPartialFileSize() throws {
        let destination = temporaryDirectory.appendingPathComponent("reconciled.mkv")
        let request = makeRequest(destination: destination, length: 8_192)
        let checkpoint = makeCheckpoint(request: request, bytesWritten: 1_024)
        let checkpointStore = makeCheckpointStore()
        try Data(repeating: 0x3A, count: 4_096).write(to: request.partialFileURL)
        try checkpointStore.save(checkpoint)

        let restoredManager = makeManager(checkpointStore: checkpointStore)

        guard case .paused(let reconciledCheckpoint) = restoredManager.state else {
            return XCTFail("Expected a restored paused state, got \(restoredManager.state).")
        }
        XCTAssertEqual(reconciledCheckpoint.bytesWritten, 4_096)
        XCTAssertEqual(try checkpointStore.load(), reconciledCheckpoint)
    }

    func testRestorationFinalizesCompletePartialFile() throws {
        let payload = Data(repeating: 0x81, count: 8_192)
        let destination = temporaryDirectory.appendingPathComponent("complete-partial.mkv")
        let request = makeRequest(destination: destination, length: Int64(payload.count))
        let checkpointStore = makeCheckpointStore()
        try payload.write(to: request.partialFileURL)
        try checkpointStore.save(
            makeCheckpoint(request: request, bytesWritten: 4_096)
        )

        let restoredManager = makeManager(checkpointStore: checkpointStore)

        XCTAssertEqual(restoredManager.state, .completed(destination))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))
        XCTAssertNil(try checkpointStore.load())
    }

    func testRestorationRejectsMissingNonEmptyPartialFile() throws {
        let destination = temporaryDirectory.appendingPathComponent("missing-partial.mkv")
        let request = makeRequest(destination: destination, length: 8_192)
        let checkpointStore = makeCheckpointStore()
        try checkpointStore.save(makeCheckpoint(request: request, bytesWritten: 1_024))

        let restoredManager = makeManager(checkpointStore: checkpointStore)

        guard case .failed(.persistence, checkpoint: nil) = restoredManager.state else {
            return XCTFail("Expected a persistence failure, got \(restoredManager.state).")
        }
        XCTAssertNil(try checkpointStore.load())
    }

    func testRestorationRejectsAndClearsCorruptCheckpoint() throws {
        let checkpointStore = makeCheckpointStore()
        let fileURL = try XCTUnwrap(checkpointStore.fileURL)
        try Data("not-json".utf8).write(to: fileURL)

        let restoredManager = makeManager(checkpointStore: checkpointStore)

        guard case .failed(.persistence, checkpoint: nil) = restoredManager.state else {
            return XCTFail("Expected a persistence failure, got \(restoredManager.state).")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeManager(
        checkpointStore: OfflineDownloadCheckpointStore? = nil
    ) -> OfflineDownloadManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OfflineDownloadManager(
            sessionConfiguration: configuration,
            checkpointStore: checkpointStore ?? makeCheckpointStore()
        )
    }

    private func makeCheckpointStore() -> OfflineDownloadCheckpointStore {
        OfflineDownloadCheckpointStore(
            fileURL: temporaryDirectory.appendingPathComponent("checkpoint.json")
        )
    }

    private func makeRequest(destination: URL, length: Int64) -> OfflineDownloadRequest {
        OfflineDownloadRequest(
            sourceURL: URL(string: "http://127.0.0.1:8090/stream/movie.mkv")!,
            destinationURL: destination,
            expectedLength: length
        )
    }

    private func makeCheckpoint(
        request: OfflineDownloadRequest,
        bytesWritten: Int64
    ) -> OfflineDownloadCheckpoint {
        OfflineDownloadCheckpoint(
            request: request,
            streamIdentity: OfflineDownloadStreamIdentity(
                contentLength: request.expectedLength,
                entityTag: #""fixture/movie.mkv""#
            ),
            bytesWritten: bytesWritten
        )
    }

    private func partialFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
    }

    private func waitForTerminalState(
        _ manager: OfflineDownloadManager,
        timeout: TimeInterval = 3
    ) async throws -> OfflineDownloadState {
        try await waitForState(manager, timeout: timeout) { !$0.isActive }
    }

    private func waitForState(
        _ manager: OfflineDownloadManager,
        timeout: TimeInterval = 3,
        predicate: (OfflineDownloadState) -> Bool
    ) async throws -> OfflineDownloadState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(manager.state) {
                return manager.state
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw TestError.timedOut(manager.state)
    }
}

private enum TestError: Error {
    case timedOut(OfflineDownloadState)
}

private final class StubURLProtocol: URLProtocol {
    struct Stub {
        let data: Data
        let advertisedLength: Int
        let chunkSize: Int
        let delayBetweenChunks: TimeInterval
        let honorsRanges: Bool
        let entityTag: String

        init(
            data: Data,
            advertisedLength: Int? = nil,
            chunkSize: Int,
            delayBetweenChunks: TimeInterval = 0,
            honorsRanges: Bool = true,
            entityTag: String = #""fixture/movie.mkv""#
        ) {
            self.data = data
            self.advertisedLength = advertisedLength ?? data.count
            self.chunkSize = chunkSize
            self.delayBetweenChunks = delayBetweenChunks
            self.honorsRanges = honorsRanges
            self.entityTag = entityTag
        }
    }

    private static let configurationLock = NSLock()
    private static var stub: Stub?
    private static var receivedRequests: [URLRequest] = []

    private let stateLock = NSLock()
    private var stopped = false

    static func configure(_ stub: Stub) {
        configurationLock.lock()
        self.stub = stub
        configurationLock.unlock()
    }

    static func reset() {
        configurationLock.lock()
        stub = nil
        receivedRequests = []
        configurationLock.unlock()
    }

    static func requestsSnapshot() -> [URLRequest] {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        return receivedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.stubAndRecord(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let requestedOffset = Self.requestedOffset(from: request)
        let isRangeResponse = stub.honorsRanges && requestedOffset != nil
        let bodyOffset = isRangeResponse ? requestedOffset! : 0
        let statusCode = isRangeResponse ? 206 : 200
        let responseLength = isRangeResponse
            ? stub.advertisedLength - bodyOffset
            : stub.advertisedLength
        var headerFields = [
            "Accept-Ranges": "bytes",
            "Content-Length": String(responseLength),
            "ETag": stub.entityTag
        ]
        if isRangeResponse {
            headerFields["Content-Range"] = "bytes \(bodyOffset)-\(stub.advertisedLength - 1)/\(stub.advertisedLength)"
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var offset = min(bodyOffset, stub.data.count)
            while offset < stub.data.count, !isStopped {
                let end = min(offset + stub.chunkSize, stub.data.count)
                client?.urlProtocol(self, didLoad: stub.data[offset..<end])
                offset = end
                if stub.delayBetweenChunks > 0 {
                    Thread.sleep(forTimeInterval: stub.delayBetweenChunks)
                }
            }
            if !isStopped {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    private static func stubAndRecord(_ request: URLRequest) -> Stub? {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        receivedRequests.append(request)
        return stub
    }

    private static func requestedOffset(from request: URLRequest) -> Int? {
        guard let value = request.value(forHTTPHeaderField: "Range"),
              value.hasPrefix("bytes="),
              value.hasSuffix("-") else {
            return nil
        }
        return Int(value.dropFirst("bytes=".count).dropLast())
    }
}

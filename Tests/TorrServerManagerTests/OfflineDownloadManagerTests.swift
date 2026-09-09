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
        StubURLProtocol.stub = nil
        cancellables = []
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testCompletesDownloadThroughPartialFile() async throws {
        let payload = Data((0..<131_072).map { UInt8($0 % 251) })
        StubURLProtocol.stub = .init(data: payload, chunkSize: 8_192)
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
        StubURLProtocol.stub = .init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.005
        )
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
        StubURLProtocol.stub = .init(
            data: payload,
            advertisedLength: 127,
            chunkSize: 128
        )
        let destination = temporaryDirectory.appendingPathComponent("wrong-size.mkv")
        let request = makeRequest(destination: destination, length: 128)
        let manager = makeManager()

        try manager.start(request)
        let state = try await waitForTerminalState(manager)

        XCTAssertEqual(
            state,
            .failed(
                .contract(.invalidContentLength(expected: 128, actual: "127")),
                partialFileURL: nil
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.partialFileURL.path))
    }

    func testInterruptedTransferKeepsNonEmptyPartialFile() async throws {
        let payload = Data(repeating: 0x7C, count: 4_096)
        StubURLProtocol.stub = .init(
            data: payload,
            advertisedLength: 8_192,
            chunkSize: 1_024
        )
        let destination = temporaryDirectory.appendingPathComponent("interrupted.mkv")
        let request = makeRequest(destination: destination, length: 8_192)
        let manager = makeManager()

        try manager.start(request)
        let state = try await waitForTerminalState(manager)

        guard case .failed(_, let partialFileURL) = state else {
            return XCTFail("Expected a failed state, got \(state).")
        }
        XCTAssertEqual(partialFileURL, request.partialFileURL)
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
        StubURLProtocol.stub = .init(
            data: payload,
            chunkSize: 4_096,
            delayBetweenChunks: 0.005
        )
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

    private func makeManager() -> OfflineDownloadManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OfflineDownloadManager(sessionConfiguration: configuration)
    }

    private func makeRequest(destination: URL, length: Int64) -> OfflineDownloadRequest {
        OfflineDownloadRequest(
            sourceURL: URL(string: "http://127.0.0.1:8090/stream/movie.mkv")!,
            destinationURL: destination,
            expectedLength: length
        )
    }

    private func waitForTerminalState(
        _ manager: OfflineDownloadManager
    ) async throws -> OfflineDownloadState {
        try await waitForState(manager) { !$0.isActive }
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

        init(
            data: Data,
            advertisedLength: Int? = nil,
            chunkSize: Int,
            delayBetweenChunks: TimeInterval = 0
        ) {
            self.data = data
            self.advertisedLength = advertisedLength ?? data.count
            self.chunkSize = chunkSize
            self.delayBetweenChunks = delayBetweenChunks
        }
    }

    static var stub: Stub?

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Accept-Ranges": "bytes",
                "Content-Length": String(stub.advertisedLength),
                "ETag": #""fixture/movie.mkv""#
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var offset = 0
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
}

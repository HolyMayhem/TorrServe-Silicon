import Combine
import Foundation

@MainActor
final class OfflineDownloadManager: ObservableObject {
    @Published private(set) var state: OfflineDownloadState = .idle
    @Published private(set) var currentRequest: OfflineDownloadRequest?

    private let sessionConfiguration: URLSessionConfiguration
    private let checkpointStore: OfflineDownloadCheckpointStore
    private var transfer: OfflineDownloadTransfer?
    private var transferID: UUID?

    init(
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        checkpointStore: OfflineDownloadCheckpointStore = OfflineDownloadCheckpointStore()
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.checkpointStore = checkpointStore
        restorePersistedState()
    }

    func start(_ request: OfflineDownloadRequest) throws {
        guard transfer == nil else {
            throw OfflineDownloadStartError.anotherDownloadIsActive
        }
        guard state.resumableCheckpoint == nil else {
            throw OfflineDownloadStartError.resumableDownloadExists
        }

        try validateCommonRequestFields(request)
        try validateNewDownloadFiles(request)
        beginTransfer(request: request, checkpoint: nil)
    }

    func pause() {
        guard let transfer,
              case .downloading(let progress) = state else {
            return
        }

        state = .pausing(progress)
        transfer.pause()
    }

    func resume() throws {
        guard transfer == nil else {
            throw OfflineDownloadStartError.anotherDownloadIsActive
        }
        guard let checkpoint = state.resumableCheckpoint else {
            throw OfflineDownloadStartError.noResumableDownload
        }

        try validateCheckpoint(checkpoint)
        beginTransfer(request: checkpoint.request, checkpoint: checkpoint)
    }

    func cancel() {
        if let transfer {
            state = .cancelling(activeProgress)
            transfer.cancel()
            return
        }

        guard let checkpoint = state.resumableCheckpoint else { return }
        do {
            if FileManager.default.fileExists(atPath: checkpoint.request.partialFileURL.path) {
                try FileManager.default.removeItem(at: checkpoint.request.partialFileURL)
            }
            try checkpointStore.clear()
            currentRequest = nil
            state = .cancelled
        } catch {
            let failure: OfflineDownloadFailure
            if error is OfflineDownloadCheckpointStoreError {
                failure = persistenceFailure(for: error)
            } else {
                failure = .fileSystem(error.localizedDescription)
            }
            state = .failed(
                failure,
                checkpoint: FileManager.default.fileExists(
                    atPath: checkpoint.request.partialFileURL.path
                ) ? checkpoint : nil
            )
        }
    }

    func reset() {
        guard transfer == nil, state.resumableCheckpoint == nil else { return }
        currentRequest = nil
        state = .idle
    }

    private func restorePersistedState() {
        do {
            guard let checkpoint = try checkpointStore.load() else { return }
            currentRequest = checkpoint.request
            state = try reconciledState(for: checkpoint)
        } catch {
            try? checkpointStore.clear()
            currentRequest = nil
            state = .failed(persistenceFailure(for: error), checkpoint: nil)
        }
    }

    private func reconciledState(
        for savedCheckpoint: OfflineDownloadCheckpoint
    ) throws -> OfflineDownloadState {
        let request = savedCheckpoint.request
        try validateCommonRequestFields(request)
        guard savedCheckpoint.streamIdentity.contentLength == request.expectedLength else {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                "The saved stream length does not match the download request."
            )
        }

        let fileManager = FileManager.default
        var partialIsDirectory: ObjCBool = false
        let partialExists = fileManager.fileExists(
            atPath: request.partialFileURL.path,
            isDirectory: &partialIsDirectory
        )
        var destinationIsDirectory: ObjCBool = false
        let destinationExists = fileManager.fileExists(
            atPath: request.destinationURL.path,
            isDirectory: &destinationIsDirectory
        )

        if destinationExists {
            guard !destinationIsDirectory.boolValue, !partialExists else {
                throw OfflineDownloadCheckpointStoreError.invalidData(
                    "Both the final destination and partial download exist."
                )
            }
            let destinationSize = try fileSize(at: request.destinationURL)
            guard destinationSize == request.expectedLength else {
                throw OfflineDownloadCheckpointStoreError.invalidData(
                    "The existing destination has an unexpected size."
                )
            }
            try checkpointStore.clear()
            return .completed(request.destinationURL)
        }

        guard !partialIsDirectory.boolValue else {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                "The partial download path is a directory."
            )
        }
        guard partialExists else {
            guard savedCheckpoint.bytesWritten == 0 else {
                throw OfflineDownloadCheckpointStoreError.invalidData(
                    "The saved partial download is missing."
                )
            }
            return .paused(savedCheckpoint)
        }

        let actualSize = try fileSize(at: request.partialFileURL)
        guard actualSize >= 0, actualSize <= request.expectedLength else {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                "The partial download is larger than the expected file."
            )
        }
        if actualSize == request.expectedLength {
            try fileManager.moveItem(
                at: request.partialFileURL,
                to: request.destinationURL
            )
            try checkpointStore.clear()
            return .completed(request.destinationURL)
        }

        let reconciledCheckpoint = OfflineDownloadCheckpoint(
            request: request,
            streamIdentity: savedCheckpoint.streamIdentity,
            bytesWritten: actualSize
        )
        try validateCheckpoint(reconciledCheckpoint)
        if reconciledCheckpoint != savedCheckpoint {
            try checkpointStore.save(reconciledCheckpoint)
        }
        return .paused(reconciledCheckpoint)
    }

    private func beginTransfer(
        request: OfflineDownloadRequest,
        checkpoint: OfflineDownloadCheckpoint?
    ) {
        currentRequest = request
        if let checkpoint {
            state = .resuming(checkpoint)
        } else {
            state = .preparing(request)
        }

        let newTransferID = UUID()
        let newTransfer = OfflineDownloadTransfer(
            request: request,
            checkpoint: checkpoint,
            sessionConfiguration: sessionConfiguration
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handle(event, transferID: newTransferID)
            }
        }
        transferID = newTransferID
        transfer = newTransfer
        newTransfer.start()
    }

    private func validateCommonRequestFields(
        _ request: OfflineDownloadRequest
    ) throws {
        guard let scheme = request.sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw OfflineDownloadStartError.invalidSourceURL
        }
        guard request.destinationURL.isFileURL,
              !request.destinationURL.hasDirectoryPath,
              !request.destinationURL.lastPathComponent.isEmpty else {
            throw OfflineDownloadStartError.invalidDestinationURL
        }
        guard request.expectedLength > 0 else {
            throw OfflineDownloadStartError.invalidExpectedLength(request.expectedLength)
        }

        let directoryURL = request.destinationURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw OfflineDownloadStartError.destinationDirectoryMissing(directoryURL)
        }
    }

    private func validateNewDownloadFiles(
        _ request: OfflineDownloadRequest
    ) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: request.destinationURL.path) else {
            throw OfflineDownloadStartError.destinationAlreadyExists(request.destinationURL)
        }
        guard !fileManager.fileExists(atPath: request.partialFileURL.path) else {
            throw OfflineDownloadStartError.partialFileAlreadyExists(request.partialFileURL)
        }
    }

    private func validateCheckpoint(
        _ checkpoint: OfflineDownloadCheckpoint
    ) throws {
        let request = checkpoint.request
        try validateCommonRequestFields(request)

        guard checkpoint.streamIdentity.contentLength == request.expectedLength else {
            throw OfflineDownloadStartError.invalidExpectedLength(
                checkpoint.streamIdentity.contentLength
            )
        }
        guard checkpoint.bytesWritten >= 0,
              checkpoint.bytesWritten < request.expectedLength else {
            throw OfflineDownloadStartError.partialFileSizeMismatch(
                expected: request.expectedLength,
                actual: checkpoint.bytesWritten
            )
        }
        guard !FileManager.default.fileExists(atPath: request.destinationURL.path) else {
            throw OfflineDownloadStartError.destinationAlreadyExists(request.destinationURL)
        }

        var isDirectory: ObjCBool = false
        let partialExists = FileManager.default.fileExists(
            atPath: request.partialFileURL.path,
            isDirectory: &isDirectory
        )
        if checkpoint.bytesWritten > 0, !partialExists {
            throw OfflineDownloadStartError.partialFileMissing(request.partialFileURL)
        }
        if partialExists {
            guard !isDirectory.boolValue else {
                throw OfflineDownloadStartError.invalidDestinationURL
            }
            let actualSize = try partialFileSize(at: request.partialFileURL)
            guard actualSize == checkpoint.bytesWritten else {
                throw OfflineDownloadStartError.partialFileSizeMismatch(
                    expected: checkpoint.bytesWritten,
                    actual: actualSize
                )
            }
        }
    }

    private func partialFileSize(at url: URL) throws -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber else {
                throw OfflineDownloadStartError.partialFileSizeMismatch(
                    expected: 0,
                    actual: -1
                )
            }
            return size.int64Value
        } catch let error as OfflineDownloadStartError {
            throw error
        } catch {
            throw OfflineDownloadStartError.partialFileMissing(url)
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber else {
                throw OfflineDownloadCheckpointStoreError.invalidData(
                    "The file size is unavailable for \(url.path)."
                )
            }
            return size.int64Value
        } catch let error as OfflineDownloadCheckpointStoreError {
            throw error
        } catch {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                error.localizedDescription
            )
        }
    }

    private func handle(
        _ event: OfflineDownloadTransfer.Event,
        transferID: UUID
    ) {
        guard self.transferID == transferID else { return }

        switch event {
        case .responseAccepted(let checkpoint):
            guard !isStopping else { return }
            do {
                try checkpointStore.save(checkpoint)
                state = .downloading(checkpoint.progress)
            } catch {
                state = .pausing(checkpoint.progress)
                transfer?.pause()
            }
        case .progress(let checkpoint):
            guard !isStopping else { return }
            state = .downloading(checkpoint.progress)
        case .paused(let checkpoint):
            clearTransfer()
            do {
                try checkpointStore.save(checkpoint)
                state = .paused(checkpoint)
            } catch {
                state = .failed(
                    persistenceFailure(for: error),
                    checkpoint: checkpoint
                )
            }
        case .completed(let destinationURL):
            clearTransfer()
            try? checkpointStore.clear()
            state = .completed(destinationURL)
        case .cancelled:
            clearTransfer()
            try? checkpointStore.clear()
            currentRequest = nil
            state = .cancelled
        case .failed(let failure, let checkpoint):
            clearTransfer()
            do {
                if let checkpoint {
                    try checkpointStore.save(checkpoint)
                } else {
                    try checkpointStore.clear()
                }
                state = .failed(failure, checkpoint: checkpoint)
            } catch {
                state = .failed(
                    persistenceFailure(for: error),
                    checkpoint: checkpoint
                )
            }
        }
    }

    private func persistenceFailure(for error: Error) -> OfflineDownloadFailure {
        .persistence(error.localizedDescription)
    }

    private var activeProgress: OfflineDownloadProgress? {
        switch state {
        case .downloading(let progress), .pausing(let progress):
            return progress
        case .resuming(let checkpoint):
            return checkpoint.progress
        case .idle, .preparing, .paused, .cancelling,
             .completed, .cancelled, .failed:
            return nil
        }
    }

    private var isStopping: Bool {
        switch state {
        case .pausing, .cancelling:
            return true
        case .idle, .preparing, .resuming, .downloading, .paused,
             .completed, .cancelled, .failed:
            return false
        }
    }

    private func clearTransfer() {
        transfer = nil
        transferID = nil
    }
}

private final class OfflineDownloadTransfer: NSObject, URLSessionDataDelegate {
    enum Event: Sendable {
        case responseAccepted(OfflineDownloadCheckpoint)
        case progress(OfflineDownloadCheckpoint)
        case paused(OfflineDownloadCheckpoint)
        case completed(URL)
        case cancelled
        case failed(OfflineDownloadFailure, checkpoint: OfflineDownloadCheckpoint?)
    }

    private enum StopRequest: Equatable {
        case none
        case pause
        case cancel
    }

    private let request: OfflineDownloadRequest
    private let originalCheckpoint: OfflineDownloadCheckpoint?
    private let sessionConfiguration: URLSessionConfiguration
    private let eventHandler: (Event) -> Void
    private let delegateQueue: OperationQueue
    private let stopLock = NSLock()

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var streamIdentity: OfflineDownloadStreamIdentity?
    private var bytesWritten: Int64
    private var partialFileExists = false
    private var stopRequest: StopRequest = .none
    private var terminalFailure: OfflineDownloadFailure?
    private var didFinish = false
    private var lastProgressDelivery = Date.distantPast

    init(
        request: OfflineDownloadRequest,
        checkpoint: OfflineDownloadCheckpoint?,
        sessionConfiguration: URLSessionConfiguration,
        eventHandler: @escaping (Event) -> Void
    ) {
        self.request = request
        originalCheckpoint = checkpoint
        self.sessionConfiguration = sessionConfiguration
        self.eventHandler = eventHandler
        streamIdentity = checkpoint?.streamIdentity
        bytesWritten = checkpoint?.bytesWritten ?? 0

        let queue = OperationQueue()
        queue.name = "com.holymayhem.torrserve.offline-download"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        delegateQueue = queue
        super.init()
    }

    func start() {
        let configuration = sessionConfiguration.copy() as? URLSessionConfiguration
            ?? URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5 * 60
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        self.session = session

        var urlRequest = URLRequest(
            url: request.sourceURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 5 * 60
        )
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let originalCheckpoint, originalCheckpoint.bytesWritten > 0 {
            urlRequest.setValue(
                "bytes=\(originalCheckpoint.bytesWritten)-",
                forHTTPHeaderField: "Range"
            )
            urlRequest.setValue(
                originalCheckpoint.streamIdentity.entityTag,
                forHTTPHeaderField: "If-Range"
            )
        }

        let task = session.dataTask(with: urlRequest)
        dataTask = task
        task.resume()
    }

    func pause() {
        requestStop(.pause)
    }

    func cancel() {
        requestStop(.cancel)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard currentStopRequest == .none else {
            completionHandler(.cancel)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            terminalFailure = .invalidHTTPResponse
            completionHandler(.cancel)
            return
        }

        do {
            if let originalCheckpoint, originalCheckpoint.bytesWritten > 0 {
                _ = try OfflineDownloadHTTPContract.validateResumeResponse(
                    httpResponse,
                    requestedOffset: originalCheckpoint.bytesWritten,
                    identity: originalCheckpoint.streamIdentity
                )
            } else {
                streamIdentity = try OfflineDownloadHTTPContract.validateInitialResponse(
                    httpResponse,
                    expectedLength: request.expectedLength
                )
            }

            try openPartialFile()
            guard let checkpoint = currentCheckpoint else {
                throw OfflineDownloadFailure.fileSystem(
                    "The TorrServer stream identity is missing."
                )
            }
            eventHandler(.responseAccepted(checkpoint))
            completionHandler(.allow)
        } catch let contractError as OfflineDownloadHTTPContractError {
            terminalFailure = .contract(contractError)
            completionHandler(.cancel)
        } catch let failure as OfflineDownloadFailure {
            terminalFailure = failure
            completionHandler(.cancel)
        } catch {
            closeAndRemoveEmptyPartialFile()
            terminalFailure = .fileSystem(error.localizedDescription)
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard terminalFailure == nil, currentStopRequest == .none else { return }
        guard let fileHandle else {
            terminalFailure = .fileSystem("The partial file is not open.")
            dataTask.cancel()
            return
        }

        let attemptedLength = bytesWritten + Int64(data.count)
        guard attemptedLength <= request.expectedLength else {
            terminalFailure = .exceededExpectedLength(
                expected: request.expectedLength,
                attempted: attemptedLength
            )
            dataTask.cancel()
            return
        }

        do {
            try fileHandle.write(contentsOf: data)
            bytesWritten = attemptedLength
            deliverProgressIfNeeded()
        } catch {
            terminalFailure = .fileSystem(error.localizedDescription)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !didFinish else { return }
        didFinish = true

        switch currentStopRequest {
        case .cancel:
            finishCancellation()
            return
        case .pause:
            finishPause()
            return
        case .none:
            break
        }

        if let terminalFailure {
            finishFailure(terminalFailure)
            return
        }
        if let error {
            let nsError = error as NSError
            finishFailure(
                .network(code: nsError.code, description: nsError.localizedDescription)
            )
            return
        }
        guard bytesWritten == request.expectedLength else {
            finishFailure(
                .incomplete(expected: request.expectedLength, actual: bytesWritten)
            )
            return
        }

        do {
            try closeFileHandle(synchronize: true)
            try FileManager.default.moveItem(
                at: request.partialFileURL,
                to: request.destinationURL
            )
            partialFileExists = false
            eventHandler(.completed(request.destinationURL))
            finishSession()
        } catch {
            finishFailure(.fileSystem(error.localizedDescription))
        }
    }

    private func requestStop(_ requestedStop: StopRequest) {
        stopLock.lock()
        if requestedStop == .cancel || stopRequest == .none {
            stopRequest = requestedStop
        }
        stopLock.unlock()
        dataTask?.cancel()
    }

    private var currentStopRequest: StopRequest {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopRequest
    }

    private var currentCheckpoint: OfflineDownloadCheckpoint? {
        guard let streamIdentity else { return originalCheckpoint }
        return OfflineDownloadCheckpoint(
            request: request,
            streamIdentity: streamIdentity,
            bytesWritten: bytesWritten
        )
    }

    private func openPartialFile() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: request.partialFileURL.path,
            isDirectory: &isDirectory
        )

        if let originalCheckpoint {
            if exists {
                guard !isDirectory.boolValue else {
                    throw OfflineDownloadFailure.fileSystem(
                        "The partial download path is a directory."
                    )
                }
                let attributes = try fileManager.attributesOfItem(
                    atPath: request.partialFileURL.path
                )
                let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                guard actualSize == originalCheckpoint.bytesWritten else {
                    throw OfflineDownloadFailure.fileSystem(
                        "The partial file size changed before resume."
                    )
                }
            } else {
                guard originalCheckpoint.bytesWritten == 0 else {
                    throw OfflineDownloadFailure.fileSystem(
                        "The partial download disappeared before resume."
                    )
                }
                try Data().write(to: request.partialFileURL, options: .withoutOverwriting)
            }
        } else {
            try Data().write(to: request.partialFileURL, options: .withoutOverwriting)
        }

        partialFileExists = true
        let handle = try FileHandle(forWritingTo: request.partialFileURL)
        let endOffset = try handle.seekToEnd()
        guard endOffset == UInt64(bytesWritten) else {
            try? handle.close()
            throw OfflineDownloadFailure.fileSystem(
                "The partial file offset changed before writing."
            )
        }
        fileHandle = handle
    }

    private func deliverProgressIfNeeded() {
        let now = Date()
        guard bytesWritten == request.expectedLength
            || now.timeIntervalSince(lastProgressDelivery) >= 0.1 else {
            return
        }
        guard let checkpoint = currentCheckpoint else { return }
        lastProgressDelivery = now
        eventHandler(.progress(checkpoint))
    }

    private func finishPause() {
        do {
            try closeFileHandle(synchronize: bytesWritten > 0)
        } catch {
            finishFailure(.fileSystem(error.localizedDescription))
            return
        }
        if bytesWritten == 0 {
            removePartialFileIfPresent()
        }

        guard let checkpoint = currentCheckpoint else {
            eventHandler(
                .failed(
                    .fileSystem("The paused stream identity is missing."),
                    checkpoint: nil
                )
            )
            finishSession()
            return
        }
        eventHandler(.paused(checkpoint))
        finishSession()
    }

    private func finishCancellation() {
        try? closeFileHandle(synchronize: false)
        do {
            if FileManager.default.fileExists(atPath: request.partialFileURL.path) {
                try FileManager.default.removeItem(at: request.partialFileURL)
            }
            partialFileExists = false
            eventHandler(.cancelled)
        } catch {
            eventHandler(
                .failed(
                    .fileSystem(error.localizedDescription),
                    checkpoint: currentCheckpoint
                )
            )
        }
        finishSession()
    }

    private func finishFailure(_ failure: OfflineDownloadFailure) {
        try? closeFileHandle(synchronize: bytesWritten > 0)

        let checkpoint: OfflineDownloadCheckpoint?
        if bytesWritten > 0 {
            checkpoint = currentCheckpoint
        } else if let originalCheckpoint, originalCheckpoint.bytesWritten > 0 {
            checkpoint = originalCheckpoint
        } else {
            removePartialFileIfPresent()
            checkpoint = nil
        }

        eventHandler(.failed(failure, checkpoint: checkpoint))
        finishSession()
    }

    private func closeFileHandle(synchronize: Bool) throws {
        guard let fileHandle else { return }
        self.fileHandle = nil

        var firstError: Error?
        if synchronize {
            do {
                try fileHandle.synchronize()
            } catch {
                firstError = error
            }
        }
        do {
            try fileHandle.close()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func closeAndRemoveEmptyPartialFile() {
        try? fileHandle?.close()
        fileHandle = nil
        if bytesWritten == 0 {
            removePartialFileIfPresent()
        }
    }

    private func removePartialFileIfPresent() {
        if partialFileExists
            || FileManager.default.fileExists(atPath: request.partialFileURL.path) {
            try? FileManager.default.removeItem(at: request.partialFileURL)
        }
        partialFileExists = false
    }

    private func finishSession() {
        dataTask = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

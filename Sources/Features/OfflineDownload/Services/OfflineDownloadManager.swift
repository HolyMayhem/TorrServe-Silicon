import Combine
import Foundation

@MainActor
final class OfflineDownloadManager: ObservableObject {
    @Published private(set) var state: OfflineDownloadState = .idle

    private let sessionConfiguration: URLSessionConfiguration
    private var transfer: OfflineDownloadTransfer?
    private var transferID: UUID?

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.sessionConfiguration = sessionConfiguration
    }

    func start(_ request: OfflineDownloadRequest) throws {
        guard transfer == nil else {
            throw OfflineDownloadStartError.anotherDownloadIsActive
        }
        try validate(request)

        state = .preparing(request)
        let newTransferID = UUID()
        let newTransfer = OfflineDownloadTransfer(
            request: request,
            sessionConfiguration: sessionConfiguration
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handle(
                    event,
                    transferID: newTransferID,
                    request: request
                )
            }
        }
        transferID = newTransferID
        transfer = newTransfer
        newTransfer.start()
    }

    func cancel() {
        guard let transfer else { return }
        let progress: OfflineDownloadProgress?
        if case .downloading(let currentProgress) = state {
            progress = currentProgress
        } else {
            progress = nil
        }
        state = .cancelling(progress)
        transfer.cancel()
    }

    func reset() {
        guard transfer == nil else { return }
        state = .idle
    }

    private func validate(_ request: OfflineDownloadRequest) throws {
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

        let fileManager = FileManager.default
        let directoryURL = request.destinationURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw OfflineDownloadStartError.destinationDirectoryMissing(directoryURL)
        }
        guard !fileManager.fileExists(atPath: request.destinationURL.path) else {
            throw OfflineDownloadStartError.destinationAlreadyExists(request.destinationURL)
        }
        guard !fileManager.fileExists(atPath: request.partialFileURL.path) else {
            throw OfflineDownloadStartError.partialFileAlreadyExists(request.partialFileURL)
        }
    }

    private func handle(
        _ event: OfflineDownloadTransfer.Event,
        transferID: UUID,
        request: OfflineDownloadRequest
    ) {
        guard self.transferID == transferID else { return }

        switch event {
        case .responseAccepted:
            guard !isCancelling else { return }
            state = .downloading(progress(for: request, bytesWritten: 0))
        case .progress(let bytesWritten):
            guard !isCancelling else { return }
            state = .downloading(progress(for: request, bytesWritten: bytesWritten))
        case .completed:
            transfer = nil
            self.transferID = nil
            state = .completed(request.destinationURL)
        case .cancelled:
            transfer = nil
            self.transferID = nil
            state = .cancelled
        case .failed(let failure, let partialFileURL):
            transfer = nil
            self.transferID = nil
            state = .failed(failure, partialFileURL: partialFileURL)
        }
    }

    private var isCancelling: Bool {
        if case .cancelling = state { return true }
        return false
    }

    private func progress(
        for request: OfflineDownloadRequest,
        bytesWritten: Int64
    ) -> OfflineDownloadProgress {
        OfflineDownloadProgress(
            destinationURL: request.destinationURL,
            partialFileURL: request.partialFileURL,
            bytesWritten: bytesWritten,
            totalBytes: request.expectedLength
        )
    }
}

private final class OfflineDownloadTransfer: NSObject, URLSessionDataDelegate {
    enum Event: Sendable {
        case responseAccepted(OfflineDownloadStreamIdentity)
        case progress(Int64)
        case completed
        case cancelled
        case failed(OfflineDownloadFailure, partialFileURL: URL?)
    }

    private let request: OfflineDownloadRequest
    private let sessionConfiguration: URLSessionConfiguration
    private let eventHandler: (Event) -> Void
    private let delegateQueue: OperationQueue
    private let cancellationLock = NSLock()

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var bytesWritten: Int64 = 0
    private var partialFileWasCreated = false
    private var cancellationRequested = false
    private var terminalFailure: OfflineDownloadFailure?
    private var didFinish = false
    private var lastProgressDelivery = Date.distantPast

    init(
        request: OfflineDownloadRequest,
        sessionConfiguration: URLSessionConfiguration,
        eventHandler: @escaping (Event) -> Void
    ) {
        self.request = request
        self.sessionConfiguration = sessionConfiguration
        self.eventHandler = eventHandler

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

        let task = session.dataTask(with: urlRequest)
        dataTask = task
        task.resume()
    }

    func cancel() {
        cancellationLock.lock()
        cancellationRequested = true
        cancellationLock.unlock()
        dataTask?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !isCancellationRequested else {
            completionHandler(.cancel)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            terminalFailure = .invalidHTTPResponse
            completionHandler(.cancel)
            return
        }

        do {
            let identity = try OfflineDownloadHTTPContract.validateInitialResponse(
                httpResponse,
                expectedLength: request.expectedLength
            )
            try Data().write(to: request.partialFileURL, options: .withoutOverwriting)
            partialFileWasCreated = true
            fileHandle = try FileHandle(forWritingTo: request.partialFileURL)
            eventHandler(.responseAccepted(identity))
            completionHandler(.allow)
        } catch let contractError as OfflineDownloadHTTPContractError {
            terminalFailure = .contract(contractError)
            completionHandler(.cancel)
        } catch {
            removeEmptyPartialFile()
            terminalFailure = .fileSystem(error.localizedDescription)
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard terminalFailure == nil, !isCancellationRequested else { return }
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

        if isCancellationRequested {
            finishCancellation()
            return
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
            partialFileWasCreated = false
            eventHandler(.progress(bytesWritten))
            eventHandler(.completed)
            finishSession()
        } catch {
            finishFailure(.fileSystem(error.localizedDescription))
        }
    }

    private var isCancellationRequested: Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return cancellationRequested
    }

    private func deliverProgressIfNeeded() {
        let now = Date()
        guard bytesWritten == request.expectedLength
            || now.timeIntervalSince(lastProgressDelivery) >= 0.1 else {
            return
        }
        lastProgressDelivery = now
        eventHandler(.progress(bytesWritten))
    }

    private func finishCancellation() {
        try? closeFileHandle(synchronize: false)
        if partialFileWasCreated {
            do {
                try FileManager.default.removeItem(at: request.partialFileURL)
                partialFileWasCreated = false
            } catch {
                eventHandler(
                    .failed(
                        .fileSystem(error.localizedDescription),
                        partialFileURL: request.partialFileURL
                    )
                )
                finishSession()
                return
            }
        }
        eventHandler(.cancelled)
        finishSession()
    }

    private func finishFailure(_ failure: OfflineDownloadFailure) {
        try? closeFileHandle(synchronize: false)

        var partialFileURL: URL?
        if partialFileWasCreated, bytesWritten > 0 {
            partialFileURL = request.partialFileURL
        } else {
            removeEmptyPartialFile()
        }

        eventHandler(.failed(failure, partialFileURL: partialFileURL))
        finishSession()
    }

    private func closeFileHandle(synchronize: Bool) throws {
        guard let fileHandle else { return }
        if synchronize {
            try fileHandle.synchronize()
        }
        try fileHandle.close()
        self.fileHandle = nil
    }

    private func removeEmptyPartialFile() {
        try? fileHandle?.close()
        fileHandle = nil
        if partialFileWasCreated {
            try? FileManager.default.removeItem(at: request.partialFileURL)
            partialFileWasCreated = false
        }
    }

    private func finishSession() {
        dataTask = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

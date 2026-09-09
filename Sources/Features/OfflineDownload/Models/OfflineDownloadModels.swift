import Foundation

struct OfflineDownloadRequest: Equatable, Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let expectedLength: Int64

    var partialFileURL: URL {
        destinationURL.appendingPathExtension("torrserve-part")
    }
}

struct OfflineDownloadProgress: Equatable, Sendable {
    let destinationURL: URL
    let partialFileURL: URL
    let bytesWritten: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(bytesWritten) / Double(totalBytes), 0), 1)
    }
}

struct OfflineDownloadCheckpoint: Equatable, Sendable {
    let request: OfflineDownloadRequest
    let streamIdentity: OfflineDownloadStreamIdentity
    let bytesWritten: Int64

    var progress: OfflineDownloadProgress {
        OfflineDownloadProgress(
            destinationURL: request.destinationURL,
            partialFileURL: request.partialFileURL,
            bytesWritten: bytesWritten,
            totalBytes: request.expectedLength
        )
    }
}

enum OfflineDownloadFailure: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case contract(OfflineDownloadHTTPContractError)
    case fileSystem(String)
    case network(code: Int?, description: String)
    case incomplete(expected: Int64, actual: Int64)
    case exceededExpectedLength(expected: Int64, attempted: Int64)
}

extension OfflineDownloadFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "TorrServer returned an invalid HTTP response."
        case .contract(let error):
            return error.localizedDescription
        case .fileSystem(let description):
            return "Could not write the offline file: \(description)"
        case .network(_, let description):
            return "The download connection failed: \(description)"
        case .incomplete(let expected, let actual):
            return "The download ended after \(actual) of \(expected) bytes."
        case .exceededExpectedLength(let expected, let attempted):
            return "TorrServer sent \(attempted) bytes for a file expected to contain \(expected)."
        }
    }
}

enum OfflineDownloadState: Equatable, Sendable {
    case idle
    case preparing(OfflineDownloadRequest)
    case resuming(OfflineDownloadCheckpoint)
    case downloading(OfflineDownloadProgress)
    case pausing(OfflineDownloadProgress)
    case paused(OfflineDownloadCheckpoint)
    case cancelling(OfflineDownloadProgress?)
    case completed(URL)
    case cancelled
    case failed(OfflineDownloadFailure, checkpoint: OfflineDownloadCheckpoint?)

    var isActive: Bool {
        switch self {
        case .preparing, .resuming, .downloading, .pausing, .cancelling:
            return true
        case .idle, .paused, .completed, .cancelled, .failed:
            return false
        }
    }

    var resumableCheckpoint: OfflineDownloadCheckpoint? {
        switch self {
        case .paused(let checkpoint):
            return checkpoint
        case .failed(_, let checkpoint):
            return checkpoint
        case .idle, .preparing, .resuming, .downloading, .pausing,
             .cancelling, .completed, .cancelled:
            return nil
        }
    }
}

enum OfflineDownloadStartError: Error, Equatable, Sendable {
    case anotherDownloadIsActive
    case resumableDownloadExists
    case noResumableDownload
    case invalidSourceURL
    case invalidDestinationURL
    case invalidExpectedLength(Int64)
    case destinationDirectoryMissing(URL)
    case destinationAlreadyExists(URL)
    case partialFileAlreadyExists(URL)
    case partialFileMissing(URL)
    case partialFileSizeMismatch(expected: Int64, actual: Int64)
}

extension OfflineDownloadStartError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .anotherDownloadIsActive:
            return "Another offline download is already active."
        case .resumableDownloadExists:
            return "Pause, resume, or cancel the existing offline download first."
        case .noResumableDownload:
            return "There is no paused or interrupted download to resume."
        case .invalidSourceURL:
            return "The TorrServer stream URL is invalid."
        case .invalidDestinationURL:
            return "The offline destination must be a file URL."
        case .invalidExpectedLength(let length):
            return "Invalid expected file length: \(length)."
        case .destinationDirectoryMissing(let url):
            return "The destination folder does not exist: \(url.path)"
        case .destinationAlreadyExists(let url):
            return "A file already exists at the destination: \(url.path)"
        case .partialFileAlreadyExists(let url):
            return "A partial download already exists: \(url.path)"
        case .partialFileMissing(let url):
            return "The partial download is missing: \(url.path)"
        case .partialFileSizeMismatch(let expected, let actual):
            return "The partial file contains \(actual) bytes; expected \(expected)."
        }
    }
}

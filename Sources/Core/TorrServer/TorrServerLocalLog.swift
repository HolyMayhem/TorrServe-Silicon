import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TorrServerLocalLog: @unchecked Sendable {
    enum Stage: String, Encodable {
        case http, decode, releaseMetadata, releaseSelection, assetDownload, assetSize
        case assetChecksum, assetArchitecture, assetVersion, assetInstall
        case executablePath, processLaunch, processStdout, processStderr, processExit, portCheck
    }

    enum Endpoint: String, Encodable {
        case echo, stat, torrents, settings, cache, upload, stream
    }

    enum Event: String, Encodable {
        case bundled, saved, savedUnavailable, bundlePathRelocated, compatibleReleaseFallback
        case connected, started, stopped, portInUse, databaseError, missingMediaTools, outputReceived
    }

    struct Failure: Encodable {
        let domain: String
        let code: Int
        let underlying: [Failure]

        init(_ error: NSError, depth: Int = 0) {
            // Error domains can also come from third-party code. Keep only known identifiers.
            let systemDomains = [
                NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain,
                NSMachErrorDomain, "kCFErrorDomainCFNetwork", "kCFErrorDomainPOSIX",
                "kCFErrorDomainOSStatus", "TorrServe.Backend"
            ]
            domain = systemDomains.contains(error.domain) ? error.domain : "other"
            code = error.code
            guard depth < 3 else {
                underlying = []
                return
            }
            let cause = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let causes = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? []
            var nested = (cause.map { [$0] } ?? []) + Array(causes.prefix(2))
            if let streamCode = error.userInfo["_kCFStreamErrorCodeKey"] as? Int,
               error.userInfo["_kCFStreamErrorDomainKey"] as? Int == 1,
               cause?.domain != NSPOSIXErrorDomain {
                nested.append(NSError(domain: NSPOSIXErrorDomain, code: streamCode))
            }
            underlying = nested.map { Failure($0, depth: depth + 1) }
        }
    }

    private struct Record: Encodable {
        let timestamp: Date
        let stage: Stage
        let endpoint: Endpoint?
        let status: Int?
        let event: Event?
        let error: Failure?
    }

    static let shared = TorrServerLocalLog(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TorrServer Manager/Diagnostics", isDirectory: true)
    )

    private let directory: URL?
    private let lock = NSLock()
    private var lastRecorded: [Data: Date] = [:]
    private let maxBytes = 64 * 1024

    init(directory: URL?) {
        self.directory = directory
    }

    func record(
        _ stage: Stage,
        endpoint: Endpoint? = nil,
        status: Int? = nil,
        error: Error? = nil,
        event: Event? = nil
    ) {
        guard let directory else { return }
        let failure = error.map { Failure($0 as NSError) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let now = Date()
        guard let signature = try? encoder.encode(
            Record(timestamp: .distantPast, stage: stage, endpoint: endpoint, status: status, event: event, error: failure)
        ), var line = try? encoder.encode(
            Record(timestamp: now, stage: stage, endpoint: endpoint, status: status, event: event, error: failure)
        ), line.count < maxBytes else { return }
        line.append(0x0a)

        lock.lock()
        defer { lock.unlock() }
        if let last = lastRecorded[signature], now.timeIntervalSince(last) < 60 { return }
        if lastRecorded.count >= 128 { lastRecorded.removeAll(keepingCapacity: true) }
        lastRecorded[signature] = now

        let manager = FileManager.default
        let file = directory.appendingPathComponent("backend.jsonl")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var data = Data()
            if let handle = try? FileHandle(forReadingFrom: file) {
                defer { try? handle.close() }
                data = try handle.read(upToCount: maxBytes) ?? Data()
            }
            while data.count + line.count > maxBytes {
                guard let end = data.firstIndex(of: 0x0a) else {
                    data.removeAll()
                    break
                }
                data.removeSubrange(...end)
            }
            data.append(line)
            try data.write(to: file, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Troubleshooting must not prevent a backend operation.
        }
    }

    func capture(_ pipe: Pipe, stage: Stage) {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            // Store fixed classifications only. Child output can contain paths, links and credentials.
            let text = String(decoding: data, as: UTF8.self).lowercased()
            let markers: [(String, Event)] = [
                ("address already in use", .portInUse),
                ("failed to open database", .databaseError),
                ("ffprobe not found", .missingMediaTools),
                ("ffprobe and avprobe not found", .missingMediaTools),
                ("start http server", .started)
            ]
            let events = Set(markers.compactMap { text.contains($0.0) ? $0.1 : nil })
            if events.isEmpty { record(stage, event: .outputReceived) }
            for event in events { record(stage, event: event) }
        }
    }
}

enum TorrServerBackendError: Int, LocalizedError, CustomNSError {
    case invalidHTTPResponse = 1, unexpectedVersion, invalidRelease, missingAsset
    case invalidSize, invalidChecksum, invalidArchitecture, versionMismatch, portOccupied

    static var errorDomain: String { "TorrServe.Backend" }
    var errorCode: Int { rawValue }

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse: return "TorrServer returned an unexpected HTTP response."
        case .unexpectedVersion: return "The server does not speak the TorrServer MatriX API."
        case .invalidRelease: return "GitHub returned an incompatible TorrServer release."
        case .missingAsset: return "The release does not contain an Apple Silicon executable."
        case .invalidSize: return "Размер скачанного файла TorrServer не совпадает с релизом."
        case .invalidChecksum: return "Контрольная сумма скачанного TorrServer не совпадает с релизом."
        case .invalidArchitecture: return "Скачанный файл не является исполняемой сборкой TorrServer для Apple Silicon."
        case .versionMismatch: return "Скачанный TorrServer не прошёл проверку версии. Предыдущая версия сохранена."
        case .portOccupied: return "Port 8090 is already in use."
        }
    }
}

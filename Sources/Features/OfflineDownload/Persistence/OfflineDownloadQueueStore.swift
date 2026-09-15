import Foundation

final class OfflineDownloadQueueStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let updatedAt: Date
        let requests: [OfflineDownloadRequest]
    }

    private static let currentSchemaVersion = 1

    private let fileManager: FileManager
    let fileURL: URL?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("OfflineDownloads", isDirectory: true)
            .appendingPathComponent("queue.json", isDirectory: false)
    }

    func load() throws -> [OfflineDownloadRequest] {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let envelope = try JSONDecoder().decode(
                Envelope.self,
                from: Data(contentsOf: fileURL)
            )
            guard envelope.schemaVersion == Self.currentSchemaVersion else {
                throw OfflineDownloadCheckpointStoreError.unsupportedSchema(
                    envelope.schemaVersion
                )
            }
            return envelope.requests
        } catch let error as OfflineDownloadCheckpointStoreError {
            throw error
        } catch let error as DecodingError {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                error.localizedDescription
            )
        } catch {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                error.localizedDescription
            )
        }
    }

    func save(_ requests: [OfflineDownloadRequest]) throws {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }
        if requests.isEmpty {
            try clear()
            return
        }

        do {
            let envelope = Envelope(
                schemaVersion: Self.currentSchemaVersion,
                updatedAt: Date(),
                requests: requests
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(envelope)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                error.localizedDescription
            )
        } catch {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                error.localizedDescription
            )
        }
    }

    func clear() throws {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        ) else { return }
        guard !isDirectory.boolValue else {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                "The queue path is a directory and was not removed."
            )
        }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                error.localizedDescription
            )
        }
    }
}

import Foundation

enum OfflineDownloadCheckpointStoreError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case invalidData(String)
    case unsupportedSchema(Int)
    case fileSystem(String)
}

extension OfflineDownloadCheckpointStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The Application Support folder is unavailable."
        case .invalidData(let description):
            return "The saved download record is invalid: \(description)"
        case .unsupportedSchema(let version):
            return "The saved download record uses unsupported schema \(version)."
        case .fileSystem(let description):
            return "The saved download record could not be updated: \(description)"
        }
    }
}

final class OfflineDownloadCheckpointStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let updatedAt: Date
        let checkpoint: OfflineDownloadCheckpoint
    }

    private static let currentSchemaVersion = 1

    private let fileManager: FileManager
    let fileURL: URL?

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() throws -> OfflineDownloadCheckpoint? {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw OfflineDownloadCheckpointStoreError.fileSystem(
                error.localizedDescription
            )
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                error.localizedDescription
            )
        }
        guard envelope.schemaVersion == Self.currentSchemaVersion else {
            throw OfflineDownloadCheckpointStoreError.unsupportedSchema(
                envelope.schemaVersion
            )
        }
        return envelope.checkpoint
    }

    func save(_ checkpoint: OfflineDownloadCheckpoint) throws {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }

        let envelope = Envelope(
            schemaVersion: Self.currentSchemaVersion,
            updatedAt: Date(),
            checkpoint: checkpoint
        )
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(envelope)
        } catch {
            throw OfflineDownloadCheckpointStoreError.invalidData(
                error.localizedDescription
            )
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
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
                "The checkpoint path is a directory and was not removed."
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

    private static func defaultFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("OfflineDownloads", isDirectory: true)
            .appendingPathComponent("checkpoint.json", isDirectory: false)
    }
}

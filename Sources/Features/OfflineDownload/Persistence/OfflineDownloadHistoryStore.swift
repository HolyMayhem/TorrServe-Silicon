import Foundation

final class OfflineDownloadHistoryStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let records: [OfflineDownloadRecord]
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

    func load() throws -> [OfflineDownloadRecord] {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == Self.currentSchemaVersion else {
                throw OfflineDownloadCheckpointStoreError.unsupportedSchema(
                    envelope.schemaVersion
                )
            }
            return envelope.records
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

    func save(_ records: [OfflineDownloadRecord]) throws {
        guard let fileURL else {
            throw OfflineDownloadCheckpointStoreError.applicationSupportUnavailable
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = Envelope(
                schemaVersion: Self.currentSchemaVersion,
                records: records.sorted { $0.completedAt < $1.completedAt }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(envelope).write(to: fileURL, options: .atomic)
        } catch let error as OfflineDownloadCheckpointStoreError {
            throw error
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
            .appendingPathComponent("completed.json", isDirectory: false)
    }
}

import Foundation

enum MetadataCacheLookup: Sendable {
    case missing
    case cached(MediaMetadata?)
}

actor MetadataCache {
    static let shared = MetadataCache()

    private struct Record: Codable {
        let metadata: MediaMetadata?
        let cachedAt: Date
    }

    private let fileManager: FileManager
    private let fileURL: URL?
    private var records: [String: Record]?
    private let foundLifetime: TimeInterval = 60 * 60 * 24 * 30
    private let notFoundLifetime: TimeInterval = 60 * 60 * 24

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func value(for key: String) -> MetadataCacheLookup {
        loadIfNeeded()
        guard let record = records?[key] else { return .missing }
        let lifetime = record.metadata == nil ? notFoundLifetime : foundLifetime
        guard Date().timeIntervalSince(record.cachedAt) < lifetime else {
            records?[key] = nil
            persist()
            return .missing
        }
        return .cached(record.metadata)
    }

    func save(_ metadata: MediaMetadata?, for key: String) {
        loadIfNeeded()
        records?[key] = Record(metadata: metadata, cachedAt: Date())
        persist()
    }

    func removeValue(for key: String) {
        loadIfNeeded()
        records?[key] = nil
        persist()
    }

    private func loadIfNeeded() {
        guard records == nil else { return }
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        else {
            records = [:]
            return
        }
        records = decoded
    }

    private func persist() {
        guard
            let fileURL,
            let records,
            let data = try? JSONEncoder().encode(records)
        else {
            return
        }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent("metadata.json", isDirectory: false)
    }
}

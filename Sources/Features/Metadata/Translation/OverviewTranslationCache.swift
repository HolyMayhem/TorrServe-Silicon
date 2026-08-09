import CryptoKit
import Foundation

actor OverviewTranslationCache {
    static let shared = OverviewTranslationCache()

    private let fileManager: FileManager
    private let fileURL: URL?
    private var storedValues: [String: String]?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        let defaultURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("overview-translations.json")
        self.fileURL = fileURL ?? defaultURL
    }

    func value(
        provider: MetadataProvider,
        mediaID: String?,
        sourceText: String,
        targetLanguage: String
    ) -> String? {
        values()[Self.key(
            provider: provider,
            mediaID: mediaID,
            sourceText: sourceText,
            targetLanguage: targetLanguage
        )]
    }

    func save(
        _ translation: String,
        provider: MetadataProvider,
        mediaID: String?,
        sourceText: String,
        targetLanguage: String
    ) {
        let cleaned = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        var updated = values()
        updated[Self.key(
            provider: provider,
            mediaID: mediaID,
            sourceText: sourceText,
            targetLanguage: targetLanguage
        )] = cleaned
        storedValues = updated
        persist(updated)
    }

    private func values() -> [String: String] {
        if let storedValues { return storedValues }
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            storedValues = [:]
            return [:]
        }
        storedValues = decoded
        return decoded
    }

    private func persist(_ values: [String: String]) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(values) else { return }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            return
        }
    }

    private static func key(
        provider: MetadataProvider,
        mediaID: String?,
        sourceText: String,
        targetLanguage: String
    ) -> String {
        let digest = SHA256.hash(data: Data(sourceText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return [
            "v1",
            provider.rawValue,
            mediaID ?? "-",
            targetLanguage,
            digest
        ].joined(separator: "|")
    }
}

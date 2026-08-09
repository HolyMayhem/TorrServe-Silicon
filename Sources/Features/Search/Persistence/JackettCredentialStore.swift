import Foundation

final class JackettCredentialStore {
    private struct Payload: Codable {
        let apiKey: String
    }

    private let fileManager = FileManager.default

    private var directoryURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
    }

    private var credentialsURL: URL? {
        directoryURL?.appendingPathComponent("jackett.json", isDirectory: false)
    }

    func read() -> String? {
        guard
            let credentialsURL,
            let data = try? Data(contentsOf: credentialsURL),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }
        return payload.apiKey
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        guard let directoryURL, let credentialsURL else { return false }

        if value.isEmpty {
            guard fileManager.fileExists(atPath: credentialsURL.path) else {
                return true
            }
            do {
                try fileManager.removeItem(at: credentialsURL)
                return true
            } catch {
                return false
            }
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directoryURL.path
            )
            let data = try JSONEncoder().encode(Payload(apiKey: value))
            try data.write(to: credentialsURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: credentialsURL.path
            )
            return true
        } catch {
            return false
        }
    }
}

import CryptoKit
import Foundation

final class TorrServerDownloader {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int64
            let digest: String?
        }
        let tag_name: String
        let assets: [Asset]
    }

    private let latestReleaseURL: URL
    private let session: URLSession
    private let destinationDirectory: URL?
    private let validateVersion: (URL, TorrServerVersion) async throws -> Void
    private var progressObservation: NSKeyValueObservation?

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/YouROK/TorrServer/releases/latest")!,
        destinationDirectory: URL? = nil,
        validateVersion: @escaping (URL, TorrServerVersion) async throws -> Void = TorrServerDownloader.validateVersion
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
        self.destinationDirectory = destinationDirectory
        self.validateVersion = validateVersion
    }

    func downloadLatestDarwinArm64(
        onProgress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                try Self.validateHTTPResponse(response)
                guard let data else { throw AppError("GitHub не вернул данные релиза.") }
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard let version = TorrServerVersion(release.tag_name),
                      let asset = release.assets.first(where: { $0.name == torrServerExecutableName }),
                      asset.size > 32 else {
                    throw AppError("В релизе не найден корректный файл TorrServer для Apple Silicon.")
                }
                self.downloadAsset(asset, version: version, onProgress: onProgress, completion: completion)
            } catch {
                self.finishDownload(.failure(error), completion: completion)
            }
        }.resume()
    }

    private func downloadAsset(
        _ asset: Release.Asset,
        version: TorrServerVersion,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let task = session.downloadTask(with: asset.browser_download_url) { temporaryURL, response, error in
            var stagingDirectory: URL?
            do {
                if let error { throw error }
                try Self.validateHTTPResponse(response)
                guard let temporaryURL else { throw AppError("Загрузка завершилась без файла.") }

                // Each version gets its own directory. Never overwrite the executable
                // that may still be serving the current playback session.
                let destination = try self.downloadDestinationURL(version: version)
                let directory = destination.deletingLastPathComponent()
                stagingDirectory = directory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stagedFile = destination.appendingPathExtension("download")
                try FileManager.default.moveItem(at: temporaryURL, to: stagedFile)
                try Self.validateExecutable(at: stagedFile, expectedSize: asset.size, digest: asset.digest)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedFile.path)

                Task {
                    do {
                        try await self.validateVersion(stagedFile, version)
                        try FileManager.default.moveItem(at: stagedFile, to: destination)
                        self.finishDownload(.success(destination), completion: completion)
                    } catch {
                        try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                        self.finishDownload(.failure(error), completion: completion)
                    }
                }
            } catch {
                if let stagingDirectory { try? FileManager.default.removeItem(at: stagingDirectory) }
                self.finishDownload(.failure(error), completion: completion)
            }
        }

        DispatchQueue.main.async {
            self.progressObservation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { _, change in
                guard let value = change.newValue, value.isFinite else { return }
                DispatchQueue.main.async { onProgress(min(max(value, 0), 1)) }
            }
            task.resume()
        }
    }

    static func validateHTTPResponse(_ response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw AppError("Не удалось скачать TorrServer: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
    }

    static func validateExecutable(at url: URL, expectedSize: Int64, digest: String? = nil) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) == expectedSize, data.count >= 32,
              Array(data.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe],
              Array(data[4..<8]) == [0x0c, 0x00, 0x00, 0x01],
              Array(data[12..<16]) == [0x02, 0x00, 0x00, 0x00] else {
            throw AppError("Скачанный файл не является полной исполняемой сборкой TorrServer для Apple Silicon.")
        }
        if let digest, digest.lowercased().hasPrefix("sha256:") {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == digest.dropFirst("sha256:".count).lowercased() else {
                throw AppError("Контрольная сумма скачанного TorrServer не совпадает с релизом.")
            }
        }
    }

    private static func validateVersion(at url: URL, expected: TorrServerVersion) async throws {
        let version = await TorrServerReleaseChecker().installedVersion(executablePath: url.path)
        guard version == expected else {
            throw AppError("Скачанный TorrServer не прошёл проверку версии. Предыдущая версия сохранена.")
        }
    }

    private func finishDownload(_ result: Result<URL, Error>, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.main.async {
            self.progressObservation = nil
            completion(result)
        }
    }

    private func downloadDestinationURL(version: TorrServerVersion) throws -> URL {
        let root: URL
        if let destinationDirectory {
            root = destinationDirectory
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = support.appendingPathComponent("TorrServer Manager", isDirectory: true)
        } else {
            throw AppError("Не удалось найти папку Application Support.")
        }
        return root.appendingPathComponent("Versions", isDirectory: true)
            .appendingPathComponent("\(version.displayName)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(torrServerExecutableName)
    }
}

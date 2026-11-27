import CryptoKit
import Foundation

final class TorrServerDownloader {
    private let latestReleaseURL: URL
    private let session: URLSession
    private let destinationDirectory: URL?
    private let validateVersion: (URL, TorrServerVersion) async throws -> Void
    private var progressObservation: NSKeyValueObservation?

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = TorrServerReleaseChecker.latestReleaseURL,
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
        downloadRelease(expectedTag: nil, onProgress: onProgress, completion: completion)
    }

    func downloadDarwinArm64(
        releaseTag: String,
        onProgress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        downloadRelease(expectedTag: releaseTag, onProgress: onProgress, completion: completion)
    }

    private func downloadRelease(
        expectedTag: String?,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                let release: TorrServerReleaseChecker.GitHubRelease
                if let expectedTag {
                    release = try await TorrServerReleaseChecker.fetchTaggedRelease(expectedTag, session: session)
                } else {
                    release = try await TorrServerReleaseChecker.fetchCompatibleRelease(
                        session: session, latestURL: latestReleaseURL
                    )
                }
                guard let version = release.matrixVersion, let asset = release.armAsset,
                      let assetURL = asset.browserDownloadURL, assetURL.scheme == "https" else {
                    TorrServerLocalLog.shared.record(.releaseSelection, error: TorrServerBackendError.missingAsset)
                    throw AppError("В релизе не найден корректный файл TorrServer для Apple Silicon.")
                }
                downloadAsset(asset, from: assetURL, version: version, onProgress: onProgress, completion: completion)
            } catch {
                finishDownload(.failure(error), completion: completion)
            }
        }
    }

    private func downloadAsset(
        _ asset: TorrServerReleaseChecker.GitHubRelease.Asset,
        from assetURL: URL,
        version: TorrServerVersion,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let task = session.downloadTask(with: assetURL) { temporaryURL, response, error in
            var stagingDirectory: URL?
            let status = (response as? HTTPURLResponse)?.statusCode
            var stage: TorrServerLocalLog.Stage = .assetDownload
            do {
                if let error { throw error }
                try Self.validateHTTPResponse(response)
                guard let temporaryURL else { throw AppError("Загрузка завершилась без файла.") }
                stage = .assetInstall

                // Each version gets its own directory. Never overwrite the executable
                // that may still be serving the current playback session.
                let destination = try self.downloadDestinationURL(version: version)
                let directory = destination.deletingLastPathComponent()
                stagingDirectory = directory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stagedFile = destination.appendingPathExtension("download")
                try FileManager.default.moveItem(at: temporaryURL, to: stagedFile)
                try Self.validateExecutable(at: stagedFile, expectedSize: asset.size, digest: asset.digest, status: status)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedFile.path)

                Task {
                    var stage: TorrServerLocalLog.Stage = .assetVersion
                    do {
                        try await self.validateVersion(stagedFile, version)
                        stage = .assetInstall
                        try FileManager.default.moveItem(at: stagedFile, to: destination)
                        self.finishDownload(.success(destination), completion: completion)
                    } catch {
                        TorrServerLocalLog.shared.record(stage, status: status, error: error)
                        try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                        self.finishDownload(.failure(error), completion: completion)
                    }
                }
            } catch {
                if stage != .assetInstall || !(error is TorrServerBackendError) {
                    TorrServerLocalLog.shared.record(stage, status: status, error: error)
                }
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

    static func validateExecutable(
        at url: URL, expectedSize: Int64, digest: String? = nil, status: Int? = nil
    ) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) == expectedSize, data.count >= 32 else {
            TorrServerLocalLog.shared.record(.assetSize, status: status, error: TorrServerBackendError.invalidSize)
            throw TorrServerBackendError.invalidSize
        }
        if let digest {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest.lowercased() == "sha256:\(actual)" else {
                TorrServerLocalLog.shared.record(.assetChecksum, status: status, error: TorrServerBackendError.invalidChecksum)
                throw TorrServerBackendError.invalidChecksum
            }
        }
        guard Array(data.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe],
              Array(data[4..<8]) == [0x0c, 0x00, 0x00, 0x01],
              Array(data[12..<16]) == [0x02, 0x00, 0x00, 0x00] else {
            TorrServerLocalLog.shared.record(.assetArchitecture, status: status, error: TorrServerBackendError.invalidArchitecture)
            throw TorrServerBackendError.invalidArchitecture
        }
    }

    private static func validateVersion(at url: URL, expected: TorrServerVersion) async throws {
        let version = try await TorrServerReleaseChecker.readInstalledVersion(at: url.path)
        guard version == expected else {
            throw TorrServerBackendError.versionMismatch
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

import Darwin
import Foundation

struct TorrServerAvailableUpdate: Equatable {
    let installedVersion: String
    let latestVersion: String
    let releaseURL: URL
}

struct TorrServerDowngradeRelease: Equatable, Identifiable {
    let tagName: String
    let version: String
    var id: String { tagName }
}

final class TorrServerReleaseChecker {
    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: URL?
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name, size, digest
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL?
        let assets: [Asset]
        let draft: Bool?
        let prerelease: Bool?

        var matrixVersion: TorrServerVersion? {
            guard draft != true, prerelease != true else { return nil }
            return TorrServerVersion(releaseTag: tagName)
        }

        var armAsset: Asset? {
            assets.first { $0.name == torrServerExecutableName && $0.size > 32 }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets, draft, prerelease
        }
    }

    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/YouROK/TorrServer/releases/latest"
    )!
    // GitHub's latest release can point to Silo, whose API is incompatible with MatriX.
    static let compatibleReleaseTag = "MatriX.147.1"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func installedVersion(executablePath: String) async -> TorrServerVersion? {
        try? await Self.readInstalledVersion(at: executablePath)
    }

    func availableUpdate(
        installedVersion installed: TorrServerVersion
    ) async throws -> TorrServerAvailableUpdate? {
        let release = try await Self.fetchCompatibleRelease(session: session)
        guard let latest = release.matrixVersion, let url = release.htmlURL,
              installed < latest else {
            return nil
        }

        return TorrServerAvailableUpdate(
            installedVersion: installed.displayName,
            latestVersion: latest.displayName,
            releaseURL: url
        )
    }

    func availableUpdate(executablePath: String) async throws -> TorrServerAvailableUpdate? {
        guard let installed = await installedVersion(executablePath: executablePath) else {
            return nil
        }
        return try await availableUpdate(installedVersion: installed)
    }

    /// Only stable Apple Silicon releases older than the actual selected binary.
    /// Bound the catalogue to GitHub's 100 most recent releases.
    func olderReleases(than installed: TorrServerVersion) async throws -> [TorrServerDowngradeRelease] {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/YouROK/TorrServer/releases?per_page=100")!,
            cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TorrServerManager", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw AppError("Не удалось получить старые релизы TorrServer с GitHub.")
        }
        return try Self.olderReleases(from: data, than: installed)
    }

    static func olderReleases(from data: Data, than installed: TorrServerVersion) throws -> [TorrServerDowngradeRelease] {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        var seen = Set<String>()
        return releases.compactMap { release -> TorrServerDowngradeRelease? in
            guard let version = release.matrixVersion, version < installed,
                  release.armAsset != nil,
                  seen.insert(version.displayName).inserted else { return nil }
            return TorrServerDowngradeRelease(tagName: release.tagName, version: version.displayName)
        }.sorted {
            // Versions above have already been parsed successfully.
            TorrServerVersion($0.version)! > TorrServerVersion($1.version)!
        }
    }

    static func url(forTag tag: String) -> URL {
        URL(string: "https://api.github.com/repos/YouROK/TorrServer/releases/tags")!
            .appendingPathComponent(tag)
    }

    static func fetchCompatibleRelease(
        session: URLSession,
        latestURL: URL = latestReleaseURL
    ) async throws -> GitHubRelease {
        let release = try await fetchRelease(at: latestURL, session: session)
        if release.matrixVersion != nil, release.armAsset?.browserDownloadURL != nil { return release }

        TorrServerLocalLog.shared.record(.releaseSelection, event: .compatibleReleaseFallback)
        return try await fetchTaggedRelease(compatibleReleaseTag, session: session)
    }

    static func fetchTaggedRelease(_ tag: String, session: URLSession) async throws -> GitHubRelease {
        let release = try await fetchRelease(at: url(forTag: tag), session: session)
        guard release.tagName == tag, release.matrixVersion != nil else {
            TorrServerLocalLog.shared.record(.releaseSelection, error: TorrServerBackendError.invalidRelease)
            throw AppError("GitHub не вернул совместимый релиз TorrServer MatriX.")
        }
        return release
    }

    private static func fetchRelease(at url: URL, session: URLSession) async throws -> GitHubRelease {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TorrServerManager", forHTTPHeaderField: "User-Agent")

        var status: Int?
        do {
            let (data, response) = try await session.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200 else {
                throw TorrServerBackendError.invalidHTTPResponse
            }
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            TorrServerLocalLog.shared.record(.releaseMetadata, status: status, error: error)
            if let status, status != 200 {
                throw AppError("GitHub не вернул релиз TorrServer (HTTP \(status)).")
            }
            throw error
        }
    }

    static func readInstalledVersion(at executablePath: String) async throws -> TorrServerVersion {
        try await Task.detached(priority: .utility) {
            let expandedPath = NSString(string: executablePath)
                .expandingTildeInPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
                throw CocoaError(.fileReadNoPermission)
            }

            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: expandedPath)
            process.arguments = ["--version"]
            process.standardOutput = output
            process.standardError = output

            let fd = output.fileHandleForReading.fileDescriptor
            guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try process.run()

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline, data.count < buffer.count {
                let count = Darwin.read(fd, &buffer, buffer.count - data.count)
                if count > 0 {
                    data.append(contentsOf: buffer.prefix(count))
                } else if !process.isRunning {
                    break
                } else {
                    usleep(20_000)
                }
            }
            if process.isRunning {
                process.terminate()
                usleep(200_000)
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                throw POSIXError(.ETIMEDOUT)
            }

            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8),
                  let version = TorrServerVersion(text) else {
                throw TorrServerBackendError.versionMismatch
            }
            return version
        }.value
    }
}

/// A downgrade test pauses automatic installation without disabling discovery.
enum TorrServerUpdatePolicy {
    static func shouldAutomaticallyInstall(
        enabled: Bool, testingDowngrade: Bool,
        failedVersion: String?, latestVersion: String
    ) -> Bool {
        enabled && !testingDowngrade && failedVersion != latestVersion
    }
}

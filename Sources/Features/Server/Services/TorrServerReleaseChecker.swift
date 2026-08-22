import Darwin
import Foundation

struct TorrServerAvailableUpdate: Equatable {
    let installedVersion: String
    let latestVersion: String
    let releaseURL: URL
}

struct TorrServerVersion: Comparable {
    let displayName: String
    private let components: [Int]

    init?(_ text: String) {
        let pattern = #"(?i)matrix\.([0-9]+(?:\.[0-9]+)*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let versionNumber = String(text[versionRange])
        let parsedComponents = versionNumber.split(separator: ".").compactMap {
            Int($0)
        }
        guard !parsedComponents.isEmpty else { return nil }

        displayName = "MatriX.\(versionNumber)"
        components = parsedComponents
    }

    static func == (lhs: TorrServerVersion, rhs: TorrServerVersion) -> Bool {
        compare(lhs.components, rhs.components) == .orderedSame
    }

    static func < (lhs: TorrServerVersion, rhs: TorrServerVersion) -> Bool {
        compare(lhs.components, rhs.components) == .orderedAscending
    }

    private static func compare(
        _ lhs: [Int],
        _ rhs: [Int]
    ) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}

final class TorrServerReleaseChecker {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/YouROK/TorrServer/releases/latest"
    )!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func installedVersion(executablePath: String) async -> TorrServerVersion? {
        await Self.installedVersion(at: executablePath)
    }

    func availableUpdate(
        installedVersion installed: TorrServerVersion
    ) async throws -> TorrServerAvailableUpdate? {
        let release = try await fetchLatestRelease()
        guard release.assets.contains(where: { $0.name == torrServerExecutableName }),
              let latest = TorrServerVersion(release.tagName),
              installed < latest else {
            return nil
        }

        return TorrServerAvailableUpdate(
            installedVersion: installed.displayName,
            latestVersion: latest.displayName,
            releaseURL: release.htmlURL
        )
    }

    func availableUpdate(executablePath: String) async throws -> TorrServerAvailableUpdate? {
        guard let installed = await installedVersion(executablePath: executablePath) else {
            return nil
        }
        return try await availableUpdate(installedVersion: installed)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(
            url: latestReleaseURL,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TorrServerManager", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppError("GitHub не вернул последний релиз TorrServer.")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private static func installedVersion(at executablePath: String) async -> TorrServerVersion? {
        await Task.detached(priority: .utility) {
            let expandedPath = NSString(string: executablePath)
                .expandingTildeInPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
                return nil
            }

            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: expandedPath)
            process.arguments = ["--version"]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
            } catch {
                return nil
            }

            let deadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < deadline {
                usleep(50_000)
            }

            if process.isRunning {
                process.terminate()
                usleep(200_000)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return TorrServerVersion(text)
        }.value
    }
}

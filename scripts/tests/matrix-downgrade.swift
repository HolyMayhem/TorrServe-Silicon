import Foundation

private final class ReleaseProtocol: URLProtocol {
    static var lastPath: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastPath = request.url?.path
        let data = Data(#"{"tag_name":"MatriX.999","assets":[]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct MatrixDowngradeChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        func release(_ tag: String, draft: Bool = false, prerelease: Bool = false,
                     asset: String = "TorrServer-darwin-arm64", size: Int = 100) -> [String: Any] {
            ["tag_name": tag, "html_url": "https://github.com/YouROK/TorrServer/releases/tag/\(tag)",
             "draft": draft, "prerelease": prerelease, "assets": [["name": asset, "size": size]]]
        }
        let fixture = [release("MatriX.146.2"), release("MatriX.147"), release("MatriX.147.1"),
                       release("MatriX.200"), release("MatriX.145", draft: true),
                       release("MatriX.144", prerelease: true), release("MatriX.143", asset: "TorrServer-linux-arm64"),
                       release("MatriX.142", size: 20), release("invalid"), release("MatriX.146.2")]
        let current = TorrServerVersion("MatriX.147.1")!
        let entries = try TorrServerReleaseChecker.olderReleases(from: JSONSerialization.data(withJSONObject: fixture), than: current)
        expect(entries.map(\.version) == ["MatriX.147", "MatriX.146.2"], "Only distinct older stable Apple Silicon releases, newest first")
        expect(TorrServerVersion("MatriX.147")! > TorrServerVersion("MatriX.146.99")!, "Numeric ordering")
        expect(TorrServerVersion("MatriX.147.0")! == TorrServerVersion("MatriX.147")!, "Equivalent versions")
        let empty = try TorrServerReleaseChecker.olderReleases(from: Data("[]".utf8), than: current)
        expect(empty.isEmpty, "Empty catalogue")
        do {
            _ = try TorrServerReleaseChecker.olderReleases(from: Data("not json".utf8), than: current)
            fatalError("Malformed catalogue must fail")
        } catch { checks += 1 }
        for enabled in [true, false] {
            expect(!TorrServerUpdatePolicy.shouldAutomaticallyInstall(enabled: enabled, testingDowngrade: true, failedVersion: nil, latestVersion: "MatriX.147.1"), "Never immediately auto-upgrade a test downgrade")
        }
        expect(TorrServerUpdatePolicy.shouldAutomaticallyInstall(enabled: true, testingDowngrade: false, failedVersion: nil, latestVersion: "MatriX.147.1"), "Normal automatic updates resume")
        expect(!TorrServerUpdatePolicy.shouldAutomaticallyInstall(enabled: false, testingDowngrade: false, failedVersion: nil, latestVersion: "MatriX.147.1"), "Respect the user's auto-update preference")
        expect(!TorrServerUpdatePolicy.shouldAutomaticallyInstall(enabled: true, testingDowngrade: false, failedVersion: "MatriX.147.1", latestVersion: "MatriX.147.1"), "Do not retry failed automatic versions")

        var selected = "previous"
        var starts: [String] = []
        var stops = 0
        let stoppedInstaller = TorrServerUpdateInstaller(
            stop: { stops += 1 }, start: { starts.append($0); return 1 },
            isRunning: { _ in true }, checkHealth: {}
        )
        try await stoppedInstaller.install(executablePath: "older", previousPath: "previous", restartingServer: false, selectPath: { selected = $0 })
        expect(selected == "older" && starts.isEmpty && stops == 0, "A stopped server stays stopped")
        try await stoppedInstaller.install(executablePath: "older", previousPath: "previous", restartingServer: true, selectPath: { selected = $0 })
        expect(selected == "older" && starts == ["older"] && stops == 1, "A running server restarts on the selected binary")

        starts = []; stops = 0; selected = "previous"
        let rollback = TorrServerUpdateInstaller(
            stop: { stops += 1 },
            start: { path in
                starts.append(path)
                if path == "older" { throw AppError("older-start-failed") }
                return 2
            }, isRunning: { $0 == 2 }, checkHealth: {}
        )
        do {
            try await rollback.install(executablePath: "older", previousPath: "previous", restartingServer: true, selectPath: { selected = $0 })
            fatalError("A failed downgrade must report failure")
        } catch {
            expect(selected == "previous" && starts == ["older", "previous"] && stops == 2, "Restore the previous selection and process on failure")
        }
        let failedRollback = TorrServerUpdateInstaller(
            stop: {}, start: { throw AppError($0 + "-failure") },
            isRunning: { _ in false }, checkHealth: {}
        )
        do {
            try await failedRollback.install(executablePath: "older", previousPath: "previous", restartingServer: true, selectPath: { selected = $0 })
            fatalError("Rollback failure must not be hidden")
        } catch {
            expect(selected == "previous", "Retain the previous executable selection even if it cannot restart")
            expect(error.localizedDescription.contains("older-failure") && error.localizedDescription.contains("previous-failure"), "Report both startup errors")
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        let downloader = TorrServerDownloader(session: URLSession(configuration: config))
        let result: Result<URL, Error> = await withCheckedContinuation { continuation in
            downloader.downloadDarwinArm64(releaseTag: "MatriX.147") { result in
                continuation.resume(returning: result)
            }
        }
        expect(ReleaseProtocol.lastPath == "/repos/YouROK/TorrServer/releases/tags/MatriX.147", "Download the chosen tag, never latest")
        switch result {
        case .success: fatalError("Reject a mismatched GitHub release before downloading a binary")
        case .failure: checks += 1
        }
        print("MatriX downgrade: \(checks) checks passed")
    }
}

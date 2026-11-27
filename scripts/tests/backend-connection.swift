import CryptoKit
import Darwin
import Foundation

private final class BackendProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let response: (Int, String)
        switch (url.host, url.lastPathComponent) {
        case ("silo.test", "echo"), ("silo.test", "stat"), ("silo.test", "torrents"), ("silo.test", "settings"):
            response = (404, "synthetic-secret magnet:?xt=urn:btih:private")
        case (_, "echo"): response = (200, "<html>Unrelated service</html>")
        case (_, "latest"):
            response = (200, #"{"tag_name":"Silo.3","assets":[{"name":"TorrServer-darwin-arm64","size":100,"browser_download_url":"https://release.test/silo"}]}"#)
        case (_, "MatriX.147.1"):
            response = (200, #"{"tag_name":"MatriX.147.1","html_url":"https://release.test/matrix","assets":[{"name":"TorrServer-darwin-arm64","size":100,"browser_download_url":"https://release.test/matrix"}]}"#)
        default: response = (500, "")
        }
        client?.urlProtocol(
            self, didReceive: HTTPURLResponse(url: url, statusCode: response.0, httpVersion: nil, headerFields: nil)!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data(response.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct BackendConnectionChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendProtocol.self]
        let session = URLSession(configuration: config)
        let release = try await TorrServerReleaseChecker.fetchCompatibleRelease(session: session)
        precondition(release.tagName == "MatriX.147.1")
        let update = try await TorrServerReleaseChecker(session: session)
            .availableUpdate(installedVersion: TorrServerVersion(releaseTag: "MatriX.145")!)
        precondition(update?.latestVersion == "MatriX.147.1")
        precondition(TorrServerVersion(releaseTag: "MatriX.147.1-rc") == nil)

        let silo = NativeTorrServerAPI(baseURL: URL(string: "http://silo.test")!, session: session)
        do {
            try await silo.checkHealth()
            fatalError("Silo must not be treated as a MatriX listener")
        } catch {}
        do {
            _ = try await silo.listTorrents()
            fatalError("A 404 library response must fail")
        } catch {}
        do {
            _ = try await silo.settings()
            fatalError("A 404 settings response must fail")
        } catch {}
        let unrelated = NativeTorrServerAPI(baseURL: URL(string: "http://other.test")!, session: session)
        do {
            try await unrelated.checkHealth()
            fatalError("HTTP 200 from an unrelated listener is not sufficient")
        } catch TorrServerBackendError.unexpectedVersion {}

        let binary = root.appendingPathComponent("fixture")
        let header = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01, 0, 0, 0, 0, 2] + [UInt8](repeating: 0, count: 19))
        try header.write(to: binary)
        let checksum = SHA256.hash(data: header).map { String(format: "%02x", $0) }.joined()
        try TorrServerDownloader.validateExecutable(at: binary, expectedSize: 32, digest: "sha256:\(checksum)")
        do {
            try TorrServerDownloader.validateExecutable(at: binary, expectedSize: 33)
            fatalError("Truncated binary must fail")
        } catch TorrServerBackendError.invalidSize {}
        do {
            try TorrServerDownloader.validateExecutable(at: binary, expectedSize: 32, digest: "sha256:incorrect")
            fatalError("Checksum mismatch must fail")
        } catch TorrServerBackendError.invalidChecksum {}
        try Data(repeating: 0, count: 32).write(to: binary)
        do {
            try TorrServerDownloader.validateExecutable(at: binary, expectedSize: 32)
            fatalError("Non-Mach-O binary must fail")
        } catch TorrServerBackendError.invalidArchitecture {}

        let bundled = root.appendingPathComponent("Bundled")
        precondition(TorrServerExecutablePath.resolve(saved: "", bundled: bundled.path) == bundled.path)
        precondition(TorrServerExecutablePath.resolve(saved: root.path, bundled: bundled.path) == bundled.path)
        precondition(TorrServerExecutablePath.resolve(saved: binary.path, bundled: bundled.path) == binary.path)
        let controller = TorrServerProcessController()
        controller.attach(to: TorrServerVersion(releaseTag: "MatriX.147.1")!)
        precondition(controller.isAvailable && controller.runningPID == nil)
        try controller.start(executablePath: "/nonexistent")
        controller.detach()
        precondition(!controller.isAvailable)
        try verifyPortConflict()

        let logDirectory = root.appendingPathComponent("log")
        let log = TorrServerLocalLog(directory: logDirectory)
        let logFile = logDirectory.appendingPathComponent("backend.jsonl")
        let cause = NSError(domain: NSPOSIXErrorDomain, code: 61, userInfo: [NSLocalizedDescriptionKey: "secret"])
        let network = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: [
            NSUnderlyingErrorKey: cause,
            NSURLErrorFailingURLErrorKey: URL(string: "http://private.test/?token=synthetic-secret")!
        ])
        log.record(.http, endpoint: .echo, status: 404, error: network)
        let pipe = Pipe()
        log.capture(pipe, stage: .processStderr)
        try pipe.fileHandleForWriting.write(contentsOf: Data(
            "listen: address already in use /Users/secret magnet:?xt=urn:btih:private\n".utf8
        ))
        try pipe.fileHandleForWriting.close()
        for _ in 0..<40 {
            if (try? String(contentsOf: logFile, encoding: .utf8).contains("portInUse")) == true { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let output = try String(contentsOf: logFile, encoding: .utf8)
        for marker in [NSURLErrorDomain, NSPOSIXErrorDomain, "-1004", "61", "404", "portInUse", "processStderr"] {
            precondition(output.contains(marker))
        }
        for marker in ["secret", "private", "magnet:", "token=", "/Users/"] { precondition(!output.contains(marker)) }
        for code in 1...700 {
            log.record(.processExit, error: NSError(domain: "synthetic-secret", code: code))
        }
        let data = try Data(contentsOf: logFile)
        precondition(data.count <= 64 * 1024)
        let lines = data.split(separator: 0x0a)
        precondition(lines.count < 700)
        for line in lines { _ = try JSONSerialization.jsonObject(with: Data(line)) }
        let mode = try FileManager.default.attributesOfItem(atPath: logFile.path)[.posixPermissions] as? NSNumber
        precondition(mode?.intValue == 0o600)
        print("Silo fallback, HTTP errors, file validation, executable selection, external ownership, bounded private logs passed.")

        if CommandLine.arguments.dropFirst(2).contains("--live-download") {
            let downloader = TorrServerDownloader(destinationDirectory: root.appendingPathComponent("downloads"))
            let url = try await withCheckedThrowingContinuation { continuation in
                downloader.downloadLatestDarwinArm64 { continuation.resume(with: $0) }
            }
            let version = try await TorrServerReleaseChecker.readInstalledVersion(at: url.path)
            print("Live GitHub release metadata, ARM download, SHA-256, Mach-O and --version passed for \(version.displayName).")
        }
        if CommandLine.arguments.dropFirst(2).contains("--live-loopback") {
            for host in ["localhost", "127.0.0.1", "[::1]"] {
                let base = URL(string: "http://\(host):8090")!
                let api = NativeTorrServerAPI(baseURL: base)
                let version = try await api.healthVersion()
                let items = try await api.listTorrents()
                _ = try await api.settings()
                let (_, response) = try await URLSession.shared.data(from: base.appendingPathComponent("stat"))
                precondition((response as? HTTPURLResponse)?.statusCode == 200)
                print("\(host): \(version.displayName), /echo /stat /torrents /settings succeeded, \(items.count) library entries.")
            }
            precondition(TorrServerProcessController.isPortOccupied())
        }
    }

    private static func verifyPortConflict() throws {
        let listener = socket(AF_INET6, SOCK_STREAM, 0)
        precondition(listener >= 0)
        defer { close(listener) }
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_addr = in6addr_any
        var length = socklen_t(address.sin6_len)
        try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                guard bind(listener, socketAddress, length) == 0, listen(listener, 1) == 0,
                      getsockname(listener, socketAddress, &length) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
        precondition(TorrServerProcessController.isPortOccupied(UInt16(bigEndian: address.sin6_port)))
    }
}

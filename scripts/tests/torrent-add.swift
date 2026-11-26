import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let apiKey = "fixture-jackett-key"
private let hash = "0123456789abcdef0123456789abcdef01234567"
private let magnet = "magnet:?xt=urn:btih:\(hash)"
private let torrent = Data("d4:infod6:lengthi1e4:name1:x12:piece lengthi16384e6:pieces20:".utf8)
    + Data(240...255) + Data(0...3) + Data("ee".utf8)

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func check(_ condition: Bool, _ label: String) throws {
    guard condition else { throw TestFailure(label) }
}

private func expectError(
    _ stage: String, _ category: String, code: Int = 0,
    _ action: () async throws -> Void
) async throws {
    do {
        try await action()
        throw TestFailure("Expected \(stage)/\(category)")
    } catch let error as TorrentAddError {
        let actual = error.diagnostic
        try check(actual.stage == stage && actual.category == category && actual.code == code,
                  "Expected \(stage)/\(category)/\(code), got \(actual)")
    }
}

private final class NetworkFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
    override func stopLoading() {}
}

private func release(_ url: String, source: TorrentSearchLinkSource = .jackett) -> JackettSearchResult {
    let link = URL(string: url)
    let isMagnet = link?.scheme?.lowercased() == "magnet"
    return JackettSearchResult(
        id: "fixture", title: "Example", summary: "", tracker: "Example",
        downloadURL: isMagnet ? nil : link, magnetURL: isMagnet ? link : nil,
        posterURL: nil, detailsURL: nil, size: 0, seeders: 0, peers: 0,
        categories: [], publishedAt: nil, infoHash: hash, year: "",
        downloadSource: source, magnetSource: source
    )
}

private func requireMagnet(_ payload: JackettDownloadPayload) throws {
    guard case .magnet(let value) = payload else { throw TestFailure("Expected a magnet payload") }
    try check(value == magnet, "Magnet payload changed")
}

private func requireTorrent(_ payload: JackettDownloadPayload) throws {
    guard case .torrent(let data, let filename) = payload else { throw TestFailure("Expected a .torrent payload") }
    try check(data == torrent && filename == "Example.torrent", "Torrent payload changed")
}

@main
private enum Checks {
    static func main() async {
        do {
            let ports = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
                .split(whereSeparator: \.isNewline)
            guard ports.count == 2 else { throw TestFailure("Fixture server did not report both ports") }
            let origin = "http://127.0.0.1:\(ports[0])"
            let external = "http://127.0.0.1:\(ports[1])"
            let configuration = JackettConfiguration(
                serverURL: "http://fixture-user:fixture-password@127.0.0.1:\(ports[0])/proxy/",
                apiKey: apiKey
            )
            try checkAddresses()
            try await checkSearchAndDownloads(origin: origin, external: external, configuration: configuration)
            try await checkInvalidResponses(origin: origin, configuration: configuration)
            try await checkTorrServer(origin: origin)
            #if os(macOS)
            try await checkSearchViewModel(origin: origin, configuration: configuration)
            #endif
            print("Jackett and TorrServer addition checks passed")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    static func checkAddresses() throws {
        func resolve(_ link: String, server: String) -> String? {
            JackettRequestScope(JackettConfiguration(serverURL: server, apiKey: apiKey))?
                .resolve(URL(string: link)!, relativeTo: nil)?.absoluteString
        }
        let path = "/dl/example?jackett_apikey=\(apiKey)&path=abc%2Fxyz"
        let remote = "https://jackett.example:9443/apps/jackett"
        let expected = remote + path
        for host in ["localhost", "127.0.1.2", "[::1]", "0.0.0.0", "172.17.0.3", "jackett", "jackett.example"] {
            try check(resolve("http://\(host):9117" + path, server: remote) == expected,
                      "Jackett address was not normalized for \(host)")
        }
        try check(resolve("/" + String(path.dropFirst()), server: remote) == expected, "Root-relative link lost the proxy path")
        try check(resolve(String(path.dropFirst()), server: remote) == expected, "Relative link lost the proxy path")
        try check(resolve(remote + path, server: remote) == expected, "Proxy path was duplicated")
        let local = "http://127.0.0.1:9117"
        try check(resolve(local + path, server: local) == local + path, "Local Jackett address changed")
        let tracker = "https://tracker.example:9443/download?token=tracker-token"
        try check(resolve(tracker, server: remote) == tracker, "Third-party tracker address changed")
        let unrelated = "http://localhost:8888/download"
        try check(resolve(unrelated, server: remote) == unrelated, "Unrelated loopback link changed")
        let disguised = "https://tracker.example" + path
        try check(resolve(disguised, server: remote) == disguised, "A third-party host was rewritten to Jackett")
        print("Address checks passed")
    }

    static func checkSearchAndDownloads(
        origin: String, external: String, configuration: JackettConfiguration
    ) async throws {
        let client = JackettClient()
        try await client.test(configuration: configuration)
        let results = try await client.search(query: "film + title", configuration: configuration)
        try check(results.count == 3, "Search lost valid results or returned an item without a link")
        for result in results {
            try check(result.preferredLinkSource == .jackett, "Search lost link provenance")
            try check(result.detailsURL?.host == "tracker.example", "Details link changed")
            try requireMagnet(try await client.download(result, configuration: configuration))
        }
        try await expectError("redirect", "credentials_or_scheme") {
            _ = try await client.search(query: "cross-origin", configuration: configuration)
        }

        let publicResults = try TorrentSearchResponseParser.parse(
            Data(#"{"hits":[{"title":"Example","hash":"HASH","seeders":20,"bytes":1000}]}"#
                .replacingOccurrences(of: "HASH", with: hash).utf8),
            provider: .knaben,
            pageURL: URL(string: "https://knaben.org/")!
        )
        guard let publicResult = publicResults.first else { throw TestFailure("Built-in search result missing") }
        let merged = TorrentSearchIdentity.merge([release(origin + "/torrent"), publicResult])
        try check(merged.count == 1 && merged[0].preferredLinkSource == .torrentSearch,
                  "Combined search lost the selected built-in link's origin")
        let builtInPayload = try await client.download(merged[0], configuration: configuration)
        guard case .magnet(let value) = builtInPayload else { throw TestFailure("Built-in magnet missing") }
        try check(TorrentSearchIdentity.hash(in: URL(string: value)) == hash, "Built-in magnet hash changed")

        for path in ["/torrent", "/chain-torrent", "/cross"] {
            try requireTorrent(try await client.download(release(origin + path), configuration: configuration))
        }
        for path in ["/magnet", "/magnet-redirect", "/chain"] {
            try requireMagnet(try await client.download(release(origin + path), configuration: configuration))
        }
        try requireTorrent(try await client.download(
            release(external + "/public?token=tracker-token"), configuration: configuration
        ))

        let failingConfiguration = URLSessionConfiguration.ephemeral
        failingConfiguration.protocolClasses = [NetworkFailureProtocol.self]
        let offline = JackettClient(sessionConfiguration: failingConfiguration)
        try requireMagnet(try await offline.download(release(magnet), configuration: configuration))
        try await expectError("download", "network", code: URLError.cannotConnectToHost.rawValue) {
            _ = try await offline.download(release(origin + "/torrent"), configuration: configuration)
        }
        print("Jackett search, redirects, credentials and TorrentSearch checks passed")
    }

    static func checkInvalidResponses(origin: String, configuration: JackettConfiguration) async throws {
        let client = JackettClient()
        try await expectError("link", "missing") {
            let result = JackettSearchResult(
                id: "fixture", title: "Example", summary: "", tracker: "", downloadURL: nil, magnetURL: nil,
                posterURL: nil, detailsURL: nil, size: 0, seeders: 0, peers: 0, categories: [],
                publishedAt: nil, infoHash: "", year: ""
            )
            _ = try await client.download(result, configuration: configuration)
        }
        try await expectError("link", "invalid") {
            _ = try await client.download(release("file:///tmp/example"), configuration: configuration)
        }
        try await expectError("download", "http", code: 404) {
            _ = try await client.download(release(origin + "/not-found"), configuration: configuration)
        }
        try await expectError("redirect", "limit") {
            _ = try await client.download(release(origin + "/loop"), configuration: configuration)
        }
        try await expectError("redirect", "invalid") {
            _ = try await client.download(release(origin + "/missing-location"), configuration: configuration)
        }
        for path in ["/cross-key", "/cross-token?token=session-secret", "/cross-chain?token=session-secret", "/cross-userinfo", "/unsafe"] {
            try await expectError("redirect", "credentials_or_scheme") {
                _ = try await client.download(release(origin + path), configuration: configuration)
            }
        }
        for (path, category) in [
            ("login", "html"), ("json", "json"), ("xml", "xml"), ("invalid", "bencode"),
            ("missing-info", "missingInfo"), ("empty", "empty")
        ] {
            try await expectError("validation", category) {
                _ = try await client.download(release(origin + "/" + path), configuration: configuration)
            }
        }
        for malformed in [
            "d4:infod4:namei-0eee", "d4:infod4:namei01eee", "d4:infod4:name999999999999999999999:xee",
            "d4:infod4:name1:xeeextra", "d4:infod4:name1:x4:name1:yee",
            "d4:infod4:name" + String(repeating: "l", count: 150) + String(repeating: "e", count: 152)
        ] {
            try await expectError("validation", "bencode") {
                try TorrentFileValidator.validate(Data(malformed.utf8))
            }
        }
        for invalidInfo in ["d4:info1:xe", "d4:infodee", "d6:nestedd4:infod4:name1:xeee"] {
            try await expectError("validation", "missingInfo") {
                try TorrentFileValidator.validate(Data(invalidInfo.utf8))
            }
        }
        print("Network, redirect and validation error checks passed")
    }

    static func checkTorrServer(origin: String) async throws {
        func api(_ mode: String) -> NativeTorrServerAPI {
            NativeTorrServerAPI(baseURL: URL(string: origin + "/" + mode)!)
        }
        let current = api("current")
        let upload = try await current.uploadTorrent(data: torrent, filename: "test.torrent")
        try check(upload.map(\.hash) == ["fixture-hash"], "Current upload response lost the added torrent")
        let legacy = try await api("legacy").uploadTorrent(data: torrent, filename: "test.torrent")
        try check(legacy.map(\.title) == ["Legacy"], "Legacy upload response changed")
        let addedMagnet = try await current.addMagnet(magnet)
        try check(addedMagnet.hash == upload[0].hash, "Manual magnet was not added")
        let library = try await current.listTorrents()
        try check(library.map(\.hash) == [addedMagnet.hash], "Library response changed")

        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("torrent")
        defer { try? FileManager.default.removeItem(at: temporaryFile) }
        try torrent.write(to: temporaryFile)
        let manual = try await current.uploadTorrent(at: temporaryFile)
        try check(manual.map(\.hash) == [addedMagnet.hash], "Manual .torrent import failed")
        try Data("<html>Log in</html>".utf8).write(to: temporaryFile)
        try await expectError("validation", "html") {
            _ = try await current.uploadTorrent(at: temporaryFile)
        }

        for mode in ["html", "invalid", "invalid-array", "unrelated", "empty", "null", "empty-array"] {
            let category = ["null", "empty-array"].contains(mode) ? "empty" : "invalid"
            try await expectError("server_response", category) {
                _ = try await api(mode).uploadTorrent(data: torrent, filename: "test.torrent")
            }
            try await expectError("server_response", category) {
                _ = try await api(mode).addMagnet(magnet)
            }
        }
        try await expectError("transfer", "http", code: 403) {
            _ = try await api("rejection").addMagnet(magnet)
        }
        let failingConfiguration = URLSessionConfiguration.ephemeral
        failingConfiguration.protocolClasses = [NetworkFailureProtocol.self]
        let offline = NativeTorrServerAPI(baseURL: URL(string: origin)!, session: URLSession(configuration: failingConfiguration))
        try await expectError("transfer", "network", code: URLError.cannotConnectToHost.rawValue) {
            _ = try await offline.addMagnet(magnet)
        }
        let error = TorrentAddError.downloadNetwork(-1004)
        try check(error.message(language: .russian, source: "Jackett").contains("скачивании через Jackett"),
                  "Russian error lost the stage or source")
        try check(error.message(language: .english, source: "Jackett").contains("downloading via Jackett"),
                  "English error lost the stage or source")
        print("TorrServer add, manual import, library and response checks passed")
    }

    #if os(macOS)
    @MainActor
    static func checkSearchViewModel(origin: String, configuration: JackettConfiguration) async throws {
        struct Credentials: JackettCredentialStoring {
            func read() -> String? { apiKey }
            func save(_ value: String) -> Bool { true }
        }
        let suite = "TorrentAddTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(configuration.serverURL, forKey: "JackettServerURL")
        let api = NativeTorrServerAPI(baseURL: URL(string: origin + "/current")!)
        let model = SearchViewModel(torrServer: api, defaults: defaults, credentialStore: Credentials())
        var additions: [(String, CatalogIdentity?)] = []
        model.onTorrentAdded = { hash, context in additions.append((hash, context?.item.id)) }

        model.query = "film + title"
        model.search(language: .english)
        try await waitUntil { !model.isSearching }
        guard let result = model.results.first(where: { $0.title == "Alias" }) else {
            throw TestFailure("Jackett result missing from SearchViewModel")
        }
        model.add(result, language: .english, serverIsRunning: true)
        try await waitUntil { model.addingResultID == nil }
        try check(additions.count == 1 && additions[0].0 == "fixture-hash" && additions[0].1 == nil,
                  "Search add did not notify the library")

        let item = CatalogItem(id: CatalogIdentity(kind: .movie, tmdbID: 42), title: "film + title",
                               originalTitle: "", overview: "", date: nil, rating: 0,
                               poster: nil, backdrop: nil, genreIDs: [])
        model.searchCatalogTorrents(CatalogTorrentContext(item: item, details: nil), language: .english)
        try await waitUntil { !model.isSearching }
        guard let catalogResult = model.results.first(where: { $0.title == "Relative" }) else {
            throw TestFailure("Jackett result missing from catalog search")
        }
        model.add(catalogResult, language: .english, serverIsRunning: true, watch: true)
        try await waitUntil { model.addingResultID == nil }
        try check(additions.count == 2 && additions[1].1 == item.id && model.playbackTorrent?.hash == "fixture-hash",
                  "Catalog add lost the library notification, metadata or playback")

        model.add(release(origin + "/html"), language: .russian, serverIsRunning: true)
        try await waitUntil { model.addingResultID == nil }
        try check(additions.count == 2 && model.alert?.message.contains("веб-страниц") == true,
                  "Invalid torrent reached the library or lost its localized error")
        print("SearchViewModel and media catalog addition checks passed")
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw TestFailure("Timed out waiting for SearchViewModel")
    }
    #endif
}

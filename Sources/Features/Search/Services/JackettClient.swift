import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class JackettClient: Sendable {
    private let session: URLSession
    private let externalSession: URLSession

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        sessionConfiguration.urlCredentialStorage = nil
        session = Self.makeSession(sessionConfiguration)

        let anonymous = sessionConfiguration.copy() as! URLSessionConfiguration
        anonymous.httpCookieStorage = nil
        anonymous.httpShouldSetCookies = false
        externalSession = Self.makeSession(anonymous)
    }

    deinit {
        session.finishTasksAndInvalidate()
        externalSession.finishTasksAndInvalidate()
    }

    private static func makeSession(_ configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration, delegate: JackettRedirectDelegate(), delegateQueue: nil)
    }

    func test(configuration: JackettConfiguration) async throws {
        let data = try await apiResponse(
            configuration: configuration,
            queryItems: [URLQueryItem(name: "t", value: "caps")]
        )
        guard data.range(of: Data("<caps".utf8)) != nil else {
            throw AppError("Jackett returned an unexpected response.")
        }
    }

    func search(
        query: String,
        configuration: JackettConfiguration
    ) async throws -> [JackettSearchResult] {
        let data = try await apiResponse(
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "t", value: "search"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "100")
            ]
        )

        let parser = JackettTorznabParser(data: data)
        return try parser.parse()
            .filter { $0.bestDownloadURL != nil }
            .sorted { left, right in
                if left.seeders != right.seeders {
                    return left.seeders > right.seeders
                }
                return left.publishedAt ?? .distantPast > right.publishedAt ?? .distantPast
            }
    }

    func download(
        _ result: JackettSearchResult,
        configuration: JackettConfiguration?
    ) async throws -> JackettDownloadPayload {
        let source = result.preferredLinkSource
        let scope = source == .jackett ? configuration.flatMap(JackettRequestScope.init) : nil
        guard let link = result.bestDownloadURL else { throw TorrentAddError.missingLink }
        if link.scheme?.lowercased() == "magnet" {
            return .magnet(try magnet(link, scope: scope))
        }
        let url: URL?
        if let scope {
            url = scope.resolve(link, relativeTo: nil)
        } else {
            url = link
        }
        guard let url, Self.isHTTP(url),
              scope != nil || source != .jackett else { throw TorrentAddError.invalidLink }

        switch try await fetch(url, scope: scope, source: source, isAPI: false) {
        case .magnet(let magnet):
            return .magnet(magnet)
        case .data(let data):
            TorrentAddDiagnostics.event(stage: "validation", source: source.rawValue, link: "torrent")
            try TorrentFileValidator.validate(data)
            return .torrent(data: data, filename: sanitizedTorrentFilename(result.title))
        }
    }

    private enum Response {
        case data(Data)
        case magnet(String)
    }

    private func fetch(
        _ initialURL: URL,
        scope: JackettRequestScope?,
        source: TorrentSearchLinkSource,
        isAPI: Bool
    ) async throws -> Response {
        var url = initialURL
        var visited = Set<URL>()
        var jackettSecrets = Set<String>()
        var canAuthorize = scope?.contains(initialURL) == true
        let stage = isAPI ? "jackett_api" : "download"
        for hop in 0...10 {
            guard visited.insert(url).inserted else { throw TorrentAddError.redirectLimit }
            let onJackett = scope?.contains(url) == true
            canAuthorize = canAuthorize && onJackett
            guard (!isAPI || canAuthorize), Self.isHTTP(url),
                  onJackett || scope?.exposesCredentials(url, additionalSecrets: jackettSecrets) != true else {
                throw hop == 0 ? TorrentAddError.invalidLink : TorrentAddError.unsafeRedirect
            }
            if canAuthorize, let scope {
                jackettSecrets.formUnion(scope.credentials(in: url))
            }

            // Each hop starts with a new request. Only the configured origin can use
            // its cookies and the Basic credentials from the saved server address.
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = canAuthorize
            if canAuthorize { scope?.authorize(&request) }

            let data: Data
            let response: URLResponse
            do {
                let transport = canAuthorize ? session : externalSession
                (data, response) = try await transport.data(for: request)
            } catch {
                try Task.checkCancellation()
                throw TorrentAddError.downloadNetwork((error as NSError).code)
            }
            guard let http = response as? HTTPURLResponse else { throw TorrentAddError.downloadHTTP(0) }
            TorrentAddDiagnostics.event(stage: stage, source: source.rawValue, link: "http", status: http.statusCode)

            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                TorrentAddDiagnostics.event(stage: "redirect", source: source.rawValue, link: "http", status: http.statusCode)
                guard let location = http.value(forHTTPHeaderField: "Location")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !location.isEmpty, let link = URL(string: location) else {
                    throw TorrentAddError.invalidRedirect
                }
                if link.scheme?.lowercased() == "magnet", !isAPI {
                    return .magnet(try magnet(link, scope: scope, additionalSecrets: jackettSecrets, isRedirect: true))
                }
                let target = scope?.resolve(link, relativeTo: url)
                    ?? URL(string: location, relativeTo: url)?.absoluteURL
                guard let target else { throw TorrentAddError.invalidRedirect }
                url = target
                continue
            }
            guard 200..<300 ~= http.statusCode else { throw TorrentAddError.downloadHTTP(http.statusCode) }
            if !isAPI, let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))),
               text.lowercased().hasPrefix("magnet:?"), let link = URL(string: text) {
                return .magnet(try magnet(link, scope: scope, additionalSecrets: jackettSecrets))
            }
            return .data(data)
        }
        throw TorrentAddError.redirectLimit
    }

    private func apiResponse(
        configuration: JackettConfiguration,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        guard let scope = JackettRequestScope(configuration) else {
            throw AppError("Enter a valid Jackett address.")
        }
        var components = URLComponents(
            url: scope.baseURL.appendingPathComponent("api/v2.0/indexers/all/results/torznab/api"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        ] + queryItems
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url else { throw AppError("Could not create the Jackett API URL.") }

        guard case .data(let data) = try await fetch(url, scope: scope, source: .jackett, isAPI: true) else {
            throw AppError("Jackett returned an unexpected response.")
        }
        if let text = String(data: data, encoding: .utf8), text.contains("<error "),
           let message = JackettTorznabParser.errorMessage(in: data) {
            throw AppError(message)
        }
        return data
    }

    private static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
            url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    private func magnet(
        _ link: URL, scope: JackettRequestScope?, additionalSecrets: Set<String> = [], isRedirect: Bool = false
    ) throws -> String {
        let value = link.absoluteString
        guard value.lowercased().hasPrefix("magnet:?"), value.count > "magnet:?".count else {
            throw isRedirect ? TorrentAddError.invalidRedirect : TorrentAddError.invalidLink
        }
        guard scope?.exposesCredentials(link, additionalSecrets: additionalSecrets) != true else {
            throw isRedirect ? TorrentAddError.unsafeRedirect : TorrentAddError.invalidLink
        }
        // TorrServer expects a lowercase scheme.
        return "magnet:" + value.dropFirst("magnet:".count)
    }

    private func sanitizedTorrentFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let value = title
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(value.isEmpty ? "download" : value).torrent"
    }
}

private final class JackettRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Inspect the original Location, including schemes such as magnet:.
        completionHandler(nil)
    }
}

import Foundation

final class JackettClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func test(configuration: JackettConfiguration) async throws {
        let url = try endpoint(
            configuration: configuration,
            queryItems: [
                URLQueryItem(name: "t", value: "caps")
            ]
        )
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        guard data.range(of: Data("<caps".utf8)) != nil else {
            throw AppError("Jackett returned an unexpected response.")
        }
    }

    func search(
        query: String,
        configuration: JackettConfiguration
    ) async throws -> [JackettSearchResult] {
        let items = [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "100")
        ]

        let url = try endpoint(
            configuration: configuration,
            queryItems: items
        )
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        let parser = JackettTorznabParser(data: data)
        let results = try parser.parse()
        return results
            .filter { $0.bestDownloadURL != nil }
            .sorted { left, right in
                if left.seeders != right.seeders {
                    return left.seeders > right.seeders
                }
                return left.publishedAt ?? .distantPast
                    > right.publishedAt ?? .distantPast
            }
    }

    func download(_ result: JackettSearchResult) async throws -> JackettDownloadPayload {
        guard let url = result.bestDownloadURL else {
            throw AppError("Jackett did not provide a torrent or magnet link.")
        }
        if url.scheme?.lowercased() == "magnet" {
            return .magnet(url.absoluteString)
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        if
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            text.lowercased().hasPrefix("magnet:?")
        {
            return .magnet(text)
        }

        guard data.count > 16 else {
            throw AppError("Jackett returned an empty torrent file.")
        }
        return .torrent(
            data: data,
            filename: sanitizedTorrentFilename(result.title)
        )
    }

    private func endpoint(
        configuration: JackettConfiguration,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard let serverURL = configuration.normalizedServerURL else {
            throw AppError("Enter a valid Jackett address.")
        }
        var components = URLComponents(
            url: serverURL
                .appendingPathComponent("api/v2.0/indexers/all/results/torznab/api"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "apikey",
                value: configuration.apiKey.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        ] + queryItems
        guard let url = components?.url else {
            throw AppError("Could not create the Jackett API URL.")
        }
        return url
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard
            let response = response as? HTTPURLResponse,
            200..<300 ~= response.statusCode
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError("Jackett returned HTTP \(status).")
        }

        if
            let text = String(data: data, encoding: .utf8),
            text.contains("<error "),
            let message = JackettTorznabParser.errorMessage(in: data)
        {
            throw AppError(message)
        }
    }

    private func sanitizedTorrentFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let value = title
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(value.isEmpty ? "download" : value).torrent"
    }
}

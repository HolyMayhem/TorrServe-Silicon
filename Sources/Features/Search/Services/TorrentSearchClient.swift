import Foundation

/// Native adapters based on prajwalch/TorrentSearch (MIT). See ThirdPartyLicenses.
final class TorrentSearchClient: TorrentSearchServing, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: configuration)
        }
    }

    func search(query: String, provider: TorrentSearchProvider) async throws -> [JackettSearchResult] {
        try Task.checkCancellation()
        let request = try Self.request(query: query, provider: provider)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard data.count <= 5_000_000 else { throw AppError("The search source returned too much data.") }
        return try TorrentSearchResponseParser.parse(data, provider: provider, pageURL: response.url ?? request.url!)
    }

    static func request(query: String, provider: TorrentSearchProvider) throws -> URLRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 500 else { throw AppError("Enter a search query of 1–500 characters.") }
        var components: URLComponents
        var body: Data?
        switch provider {
        case .knaben:
            components = URLComponents(string: "https://api.knaben.org/v1")!
            body = try JSONSerialization.data(withJSONObject: ["query": query, "size": 300, "order_by": "seeders", "order_direction": "desc", "hide_unsafe": true, "hide_xxx": true])
        case .torrentsCSV:
            components = URLComponents(string: "https://torrents-csv.com/service/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .yts:
            components = URLComponents(string: "https://movies-api.accel.li/api/v2/list_movies.json")!
            components.queryItems = [URLQueryItem(name: "query_term", value: query), URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "sort_by", value: "seeds"), URLQueryItem(name: "order_by", value: "desc")]
        case .nyaa:
            components = URLComponents(string: "https://nyaa.si/")!
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "f", value: "0"), URLQueryItem(name: "c", value: "0_0"), URLQueryItem(name: "s", value: "seeders"), URLQueryItem(name: "o", value: "desc")]
        case .rutor:
            components = URLComponents(string: "https://rutor.info")!
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { throw AppError("Invalid search query.") }
            components.percentEncodedPath = "/search/0/0/010/2/" + encoded
        }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw AppError("Could not create the search URL.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("TorrServeSilicon/2.8 (macOS; native torrent search)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CUBCatalogService: Sendable {
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }()

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.sharedSession
    }

    func page(for listing: CatalogListing, page: Int, connection: CatalogConnection) async throws -> CatalogPage {
        switch listing {
        case .collection(let collection):
            switch collection {
            case .trending:
                return try await both(page, connection, parameters: ["sort": "now_playing"])
            case .topRated:
                return try await both(page, connection, parameters: ["sort": "top", "vote": "8-10"])
            case .popularMovies, .popularTV, .newMovies, .upcoming:
                let sort = collection == .upcoming ? "upcoming" : collection == .newMovies ? "latest" : "top"
                let result = try await results(
                    kind: collection == .popularTV ? .tv : .movie,
                    page: page, connection: connection, parameters: ["sort": sort]
                )
                guard collection == .upcoming || collection == .newMovies else { return result }
                let today = TMDBCatalogService.day(.now)
                let recent = TMDBCatalogService.day(Calendar(identifier: .gregorian)
                    .date(byAdding: .month, value: -3, to: .now) ?? .now)
                let items = result.items.filter {
                    guard let date = $0.date, date.count == 10 else { return false }
                    return collection == .upcoming ? date > today : (recent...today).contains(date)
                }
                return CatalogPage(items: items, number: page, totalPages: result.totalPages)
            }
        case .discover(let filter):
            var parameters = ["sort": "top"]
            if let genre = filter.genreID { parameters["genre"] = String(genre) }
            if let rating = filter.minimumRating { parameters["vote"] = "\(rating)-10" }
            return try await filtered(filter, page: page, connection: connection, parameters: parameters)
        case .search(let query, let filter):
            return try await filtered(filter, page: page, connection: connection, parameters: ["query": query])
        }
    }

    private func filtered(
        _ filter: CatalogFilter, page: Int, connection: CatalogConnection, parameters: [String: String]
    ) async throws -> CatalogPage {
        if let kind = filter.effectiveKind {
            return try await results(kind: kind, page: page, connection: connection, parameters: parameters)
                .filtered(by: filter)
        }
        return try await both(page, connection, parameters: parameters).filtered(by: filter)
    }

    private func both(_ page: Int, _ connection: CatalogConnection, parameters: [String: String]) async throws -> CatalogPage {
        async let movies = results(kind: .movie, page: page, connection: connection, parameters: parameters)
        async let series = results(kind: .tv, page: page, connection: connection, parameters: parameters)
        return try await .combined(movies, series)
    }

    private func results(
        kind: MediaKind, page: Int, connection: CatalogConnection, parameters: [String: String]
    ) async throws -> CatalogPage {
        var query = parameters
        let base: URL
        if parameters["query"] != nil {
            base = connection.cubURL.appendingPathComponent("search/\(kind.rawValue)")
        } else {
            base = connection.cubURL.appendingPathComponent("", isDirectory: true)
            query["cat"] = kind.rawValue
        }
        query["page"] = String(page)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw MetadataServiceError.invalidRequest }
        var request = URLRequest(url: url, timeoutInterval: connection.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !connection.cubToken.isEmpty { request.setValue(connection.cubToken, forHTTPHeaderField: "token") }

        let data = try await MetadataHTTPTransport.data(for: request, session: session)
        guard data.count <= 2_000_000 else { throw MetadataServiceError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try MetadataHTTPTransport.decode(CatalogResponse.self, from: data, using: decoder)
        return try response.page(page, kind: kind)
    }
}

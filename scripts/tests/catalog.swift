import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct CatalogTestFailure: Error {
    let message: String
}

private func expect(_ value: Bool, _ message: String) throws {
    if !value { throw CatalogTestFailure(message: message) }
}

private struct TestTMDBConfiguration: TMDBConfigurationProviding {
    func tmdbConfiguration() -> TMDBConfiguration? {
        TMDBConfiguration(apiKey: "fixture-key", apiBaseURL: URL(string: "https://tmdb.fixture/3")!)
    }
}

private final class CatalogFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let path = url.path
        let page = query.first { $0.name == "page" }?.value ?? "1"
        let status: Int
        let body: String
        switch (url.host, path) {
        case ("tmdb.fixture", "/3/movie/popular"):
            status = query.contains(URLQueryItem(name: "api_key", value: "fixture-key")) ? 503 : 401
            body = "{}"
        case ("tmdb.fixture", "/3/movie/top_rated"):
            status = 200
            body = #"{"page":1,"total_pages":1,"results":[{"id":7,"title":"Rated Movie"}]}"#
        case ("tmdb.fixture", "/3/tv/top_rated"):
            status = 200
            body = #"{"page":1,"total_pages":1,"results":[{"id":8,"name":"Rated Show"}]}"#
        case ("tmdb.fixture", "/3/genre/tv/list"):
            status = 200
            body = #"{"genres":[{"id":18,"name":"Drama"}]}"#
        case ("cub.fixture", "/catalog"), ("cub.fixture", "/catalog/"):
            status = request.value(forHTTPHeaderField: "token") == "fixture-token" ? 200 : 401
            body = """
                {"total_pages":2,"results":[
                  {"id":\(page),"title":"Фильм","original_title":"Movie","release_date":"2024-01-03",
                   "genre_ids":[28],"vote_average":8.5,"poster_path":"/cover.jpg"},
                  {"id":\(page),"title":"Duplicate"},{"id":100,"title":"Hidden","adult":true}
                ]}
                """
        case ("cub.fixture", "/catalog/search/tv"):
            status = query.contains(URLQueryItem(name: "query", value: "A+B")) &&
                components?.percentEncodedQuery?.contains("A%2BB") == true ? 200 : 400
            body = """
                {"total_pages":1,"results":[{"id":1,"title":"Сериал","original_title":"Series",
                  "release_date":"2024-08-05","vote_average":7,"genre_ids":[18]}]}
                """
        case ("tmdb.fixture", "/3/tv/1"):
            status = 200
            body = """
                {"id":1,"name":"Сериал","original_name":"Series","first_air_date":"2024-08-05",
                 "overview":"Synopsis","vote_average":9,"episode_run_time":[42],"genres":[{"id":18,"name":"Drama"}],
                 "credits":{"cast":[{"name":"Actor","character":"Lead","profile_path":"/actor.jpg"}]},
                 "videos":{"results":[{"site":"YouTube","type":"Trailer","key":"abcdefghijk"}]},
                 "seasons":[{"id":3,"name":"Season 1","season_number":1,"episode_count":8}],
                 "similar":{"total_pages":1,"results":[{"id":2,"name":"Related"}]}}
                """
        default:
            status = 404
            body = "{}"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct CatalogChecks {
    static func main() async throws {
        let tmdbRequest = URLRequest(url: URL(string: "https://api.themoviedb.org/3/movie/popular")!)
        let posterRequest = URLRequest(url: URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg")!)
        let proxyRequest = URLRequest(url: URL(string: "https://proxy.fixture/3/movie/popular")!)
        try expect(TMDBSecureDNS.canRetry(tmdbRequest, after: URLError(.cannotConnectToHost)),
                   "A failed direct TMDB connection should try secure DNS")
        try expect(TMDBSecureDNS.canRetry(posterRequest, after: URLError(.cannotFindHost)),
                   "A failed TMDB poster lookup should try secure DNS")
        try expect(!TMDBSecureDNS.canRetry(proxyRequest, after: URLError(.cannotFindHost)),
                   "Configured third-party hosts must use their own DNS")
        try expect(!TMDBSecureDNS.canRetry(tmdbRequest, after: URLError(.serverCertificateUntrusted)),
                   "Secure DNS must not retry untrusted TLS")
        try expect(!TMDBSecureDNS.canRetry(tmdbRequest, after: MetadataServiceError.httpStatus(401)),
                   "Secure DNS must not retry API authentication failures")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFixture.self]
        let session = URLSession(configuration: configuration)
        var repository = CatalogRepository()
        repository.tmdb = TMDBCatalogService(tmdb: TMDBService(configurationProvider: TestTMDBConfiguration(), session: session))
        repository.cub = CUBCatalogService(session: session)

        let connection = CatalogConnection(
            source: .auto, cubURL: URL(string: "https://cub.fixture/catalog")!, cubToken: "fixture-token"
        )

        let first = try await repository.page(.collection(.popularMovies), number: 1, language: "ru-RU", connection: connection)
        try expect(first.source == .cub, "Auto should fall back after a TMDB failure")
        try expect(first.page.items.count == 1, "Duplicate and adult items should be removed")
        try expect(first.page.number == 1 && first.page.totalPages == 2, "CUB pagination should be preserved")
        guard let movie = first.page.items.first else { throw CatalogTestFailure(message: "Missing movie") }
        try expect(movie.id.kind == .movie && movie.id.tmdbID == 1, "CUB should preserve the movie TMDB ID")
        try expect(movie.year == 2024 && movie.rating == 8.5 && movie.poster?.host == "image.tmdb.org", "Card fields should decode")

        let next = try await repository.page(
            .collection(.popularMovies), number: 2, language: "ru-RU", connection: connection, preferredSource: first.source
        )
        try expect(next.page.items.first?.id.tmdbID == 2, "The next page should stay with the chosen provider")
        let restarted = try await repository.page(.collection(.popularMovies), number: 2, language: "ru-RU", connection: connection)
        try expect(restarted.source == .cub && restarted.page.number == 1, "Switching providers should restart pagination")

        var cub = connection
        cub.source = .cub
        let seriesPage = try await repository.page(
            .search("A+B", CatalogFilter(kind: .tv, genreID: 18, year: 2024, minimumRating: 7)),
            number: 1, language: "ru-RU", connection: cub
        )
        guard let series = seriesPage.page.items.first else { throw CatalogTestFailure(message: "Missing series") }
        try expect(series.id != movie.id && series.id.tmdbID == movie.id.tmdbID, "Equal numeric IDs for different media types must remain distinct")
        try expect(series.originalTitle == "Series" && series.year == 2024, "CUB TV aliases should normalize")
        let filtered = try await repository.page(
            .search("A+B", CatalogFilter(kind: .tv, year: 2023)), number: 1, language: "ru-RU", connection: cub
        )
        try expect(filtered.page.items.isEmpty, "Unsupported year filters should be applied locally")

        let details = try await repository.details(series.id, language: "ru-RU", connection: cub.tmdb)
        try expect(details.runtime == 42 && details.cast.first?.name == "Actor", "TMDB should supply runtime and cast")
        try expect(details.seasons.first?.episodeCount == 8 && details.similar.first?.id.tmdbID == 2, "Seasons and similar titles should decode")
        try expect(details.trailer?.host == "www.youtube.com", "A supported trailer should produce a link")
        try expect(CatalogTorrentContext(item: series, details: details).queries == ["Сериал 2024", "Series 2024"],
                   "Torrent searches should use localized and original title and year")
        try await checkOutageSimulation(repository: repository, connection: connection, series: series.id)
        try checkFailureReasons()
        try expect(CatalogConnection.endpoint("https://user:secret@host.test") == nil &&
                   CatalogConnection.endpoint("http://host.test") == nil, "Catalog endpoints must use HTTPS without credentials")
        try expect(CatalogImageURL.make("/../poster.png", size: "w342") == nil, "Artwork must be a simple TMDB path")

        let legacy = try JSONDecoder().decode(LibraryMetadata.self, from: Data(#"{"title":"Legacy","tmdbID":1}"#.utf8))
        try expect(legacy.catalogIdentity == nil && legacy.metadataProvider == .tmdb, "Existing library metadata must remain readable")
        let linked = LibraryMetadata(title: "Series", posterURL: "", summary: "", source: "TMDB", tmdbID: 1, catalogIdentity: series.id)
        let reopened = try JSONDecoder().decode(LibraryMetadata.self, from: JSONEncoder().encode(linked))
        try expect(reopened.catalogIdentity == series.id, "Library links must survive reloading")
        print("Catalog checks passed")
    }

    private static func checkOutageSimulation(
        repository: CatalogRepository, connection: CatalogConnection, series: CatalogIdentity
    ) async throws {
        let rated = CatalogListing.collection(.topRated)
        let popular = CatalogListing.collection(.popularMovies)
        let language = "ru-RU"
        let healthy = try await repository.page(rated, number: 1, language: language, connection: connection)
        try expect(healthy.source == .tmdb, "Auto should prefer TMDB when both sources work")
        let genres = try await repository.genres(kind: .tv, language: language, connection: connection.tmdb)
        try expect(genres.first?.id == 18, "TMDB genres should be cached before simulation")

        var simulated = connection
        simulated.tmdb.simulatesOutage = true
        let fallback = try await repository.page(rated, number: 1, language: language, connection: simulated)
        try expect(fallback.source == .cub, "A cached TMDB page must not hide a simulated TMDB outage")
        try await expectOffline {
            _ = try await repository.details(series, language: language, connection: simulated.tmdb)
        }
        try await expectOffline {
            _ = try await repository.genres(kind: .tv, language: language, connection: simulated.tmdb)
        }
        simulated.source = .tmdb
        try await expectFailure([.init(source: .tmdb, reason: .simulated)]) {
            _ = try await repository.page(rated, number: 1, language: language, connection: simulated)
        }

        simulated = connection
        simulated.simulatesCUBOutage = true
        let tmdbOnly = try await repository.page(rated, number: 1, language: language, connection: simulated)
        try expect(tmdbOnly.source == .tmdb, "TMDB should stay available during a CUB outage")
        try await expectFailure([.init(source: .tmdb, reason: .serviceError(503)), .init(source: .cub, reason: .simulated)]) {
            _ = try await repository.page(popular, number: 1, language: language, connection: simulated)
        }
        simulated.source = .cub
        try await expectFailure([.init(source: .cub, reason: .simulated)]) {
            _ = try await repository.page(popular, number: 1, language: language, connection: simulated)
        }

        simulated.source = .auto
        simulated.tmdb.simulatesOutage = true
        try await expectFailure([.init(source: .tmdb, reason: .simulated), .init(source: .cub, reason: .simulated)]) {
            _ = try await repository.page(rated, number: 1, language: language, connection: simulated)
        }
        let recovered = try await repository.page(rated, number: 1, language: language, connection: connection)
        try expect(recovered.source == .tmdb, "Disabling simulation should restore the real catalog")

        var invalidToken = connection
        invalidToken.cubToken = "rejected-token"
        try await expectFailure([.init(source: .tmdb, reason: .serviceError(503)), .init(source: .cub, reason: .accessDenied(401))]) {
            _ = try await repository.page(popular, number: 1, language: language, connection: invalidToken)
        }
    }

    private static func expectFailure(
        _ attempts: [CatalogLoadFailure.Attempt],
        _ request: () async throws -> Void
    ) async throws {
        do {
            try await request()
            throw CatalogTestFailure(message: "Expected a catalog load failure")
        } catch let failure as CatalogLoadFailure {
            try expect(failure.attempts == attempts, "Expected \(attempts), got \(failure.attempts)")
        }
    }

    private static func checkFailureReasons() throws {
        let cases: [(Error, CatalogLoadFailure.Reason)] = [
            (URLError(.notConnectedToInternet), .offline),
            (URLError(.cannotFindHost), .dns),
            (URLError(.dnsLookupFailed), .dns),
            (URLError(.cannotConnectToHost), .connection),
            (URLError(.networkConnectionLost), .connection),
            (URLError(.timedOut), .timeout),
            (URLError(.serverCertificateUntrusted), .secureConnection),
            (URLError(.badURL), .invalidRequest),
            (URLError(.dataNotAllowed), .otherNetworkError(URLError.Code.dataNotAllowed.rawValue)),
            (MetadataServiceError.notConfigured(.tmdb), .missingKey),
            (MetadataServiceError.invalidRequest, .invalidRequest),
            (MetadataServiceError.httpStatus(403), .accessDenied(403)),
            (MetadataServiceError.httpStatus(451), .accessDenied(451)),
            (MetadataServiceError.httpStatus(429), .rateLimited),
            (MetadataServiceError.httpStatus(502), .serviceError(502)),
            (MetadataServiceError.httpStatus(302), .unexpectedHTTPStatus(302)),
            (MetadataServiceError.decodingFailed, .invalidResponse),
            (MetadataServiceError.api("raw response contents"), .invalidResponse),
            (CatalogTestFailure(message: "unexpected error"), .unknown)
        ]
        for (error, reason) in cases {
            try expect(CatalogLoadFailure.Reason(error) == reason, "Wrong diagnosis for \(error)")
        }
    }

    private static func expectOffline(_ request: () async throws -> Void) async throws {
        do {
            try await request()
            throw CatalogTestFailure(message: "Expected a simulated provider outage")
        } catch let error as URLError where error.code == .notConnectedToInternet {}
    }
}

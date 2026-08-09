import Foundation

final class TMDBService: MetadataServicing, @unchecked Sendable {
    let provider = MetadataProvider.tmdb

    private let configurationProvider: TMDBConfigurationProviding
    private let session: URLSession

    init(
        configurationProvider: TMDBConfigurationProviding = MetadataSettingsStore.shared,
        session: URLSession = .shared
    ) {
        self.configurationProvider = configurationProvider
        self.session = session
    }

    func search(
        title: String,
        year: Int?,
        kind: MediaKind,
        language: String
    ) async throws -> [MediaSearchResult] {
        var queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page", value: "1")
        ]
        if let year {
            queryItems.append(URLQueryItem(
                name: kind == .movie ? "primary_release_year" : "first_air_date_year",
                value: String(year)
            ))
        }

        let envelope: SearchEnvelope = try await request(
            path: "search/\(kind.rawValue)",
            queryItems: queryItems
        )
        return envelope.results.map { $0.result(kind: kind) }
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        guard Int(id) != nil else { throw MetadataServiceError.invalidRequest }
        switch kind {
        case .movie:
            let value: MovieDetailsDTO = try await request(
                path: "movie/\(id)",
                queryItems: [URLQueryItem(name: "language", value: language)]
            )
            return value.metadata

        case .tv:
            let value: TVDetailsDTO = try await request(
                path: "tv/\(id)",
                queryItems: [URLQueryItem(name: "language", value: language)]
            )
            return value.metadata
        }
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard let configuration = configurationProvider.tmdbConfiguration() else {
            throw MetadataServiceError.notConfigured(.tmdb)
        }

        var components = URLComponents(
            url: configuration.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems + [
            URLQueryItem(name: "api_key", value: configuration.apiKey)
        ]
        guard let url = components?.url else {
            throw MetadataServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MetadataServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw MetadataServiceError.httpStatus(http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed
        }
    }
}

private struct SearchEnvelope: Decodable {
    let results: [SearchResultDTO]
}

private struct SearchResultDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let voteAverage: Double?
    let popularity: Double?

    func result(kind: MediaKind) -> MediaSearchResult {
        MediaSearchResult(
            id: String(id),
            provider: .tmdb,
            kind: kind,
            localizedTitle: title ?? name ?? originalTitle ?? originalName ?? "",
            originalTitle: originalTitle ?? originalName ?? title ?? name ?? "",
            releaseDate: releaseDate ?? firstAirDate,
            posterURL: TMDBImageURL.make(path: posterPath, size: "w500"),
            backdropURL: TMDBImageURL.make(path: backdropPath, size: "w1280"),
            overview: overview ?? "",
            rating: voteAverage ?? 0,
            popularity: popularity ?? 0
        )
    }
}

private struct TMDBGenreDTO: Decodable {
    let id: Int
    let name: String
}

private struct MovieDetailsDTO: Decodable {
    let id: Int
    let title: String
    let originalTitle: String
    let overview: String?
    let genres: [TMDBGenreDTO]
    let runtime: Int?
    let releaseDate: String?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?

    var metadata: MediaMetadata {
        MediaMetadata(
            id: String(id),
            provider: .tmdb,
            kind: .movie,
            localizedTitle: title,
            originalTitle: originalTitle,
            overview: overview ?? "",
            genres: genres.map(\.name),
            runtimeMinutes: runtime,
            releaseDate: releaseDate,
            rating: voteAverage ?? 0,
            posterURL: TMDBImageURL.make(path: posterPath, size: "w500"),
            backdropURL: TMDBImageURL.make(path: backdropPath, size: "w1280")
        )
    }
}

private struct TVDetailsDTO: Decodable {
    let id: Int
    let name: String
    let originalName: String
    let overview: String?
    let genres: [TMDBGenreDTO]
    let episodeRunTime: [Int]?
    let firstAirDate: String?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?

    var metadata: MediaMetadata {
        MediaMetadata(
            id: String(id),
            provider: .tmdb,
            kind: .tv,
            localizedTitle: name,
            originalTitle: originalName,
            overview: overview ?? "",
            genres: genres.map(\.name),
            runtimeMinutes: episodeRunTime?.first,
            releaseDate: firstAirDate,
            rating: voteAverage ?? 0,
            posterURL: TMDBImageURL.make(path: posterPath, size: "w500"),
            backdropURL: TMDBImageURL.make(path: backdropPath, size: "w1280")
        )
    }
}

private enum TMDBImageURL {
    static func make(path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

import Foundation

struct TMDBCatalogService: Sendable {
    let tmdb: TMDBService

    func page(for listing: CatalogListing, page: Int, language: String) async throws -> CatalogPage {
        switch listing {
        case .collection(let collection):
            var parameters: [String: String] = [:]
            let path: String
            let kind: MediaKind?
            switch collection {
            case .trending: (path, kind) = ("trending/all/week", nil)
            case .newMovies:
                (path, kind) = ("discover/movie", .movie)
                let today = Date.now
                let firstDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: -3, to: today) ?? today
                parameters["primary_release_date.gte"] = Self.day(firstDate)
                parameters["primary_release_date.lte"] = Self.day(today)
                parameters["sort_by"] = "popularity.desc"
            case .popularMovies: (path, kind) = ("movie/popular", .movie)
            case .popularTV: (path, kind) = ("tv/popular", .tv)
            case .upcoming:
                (path, kind) = ("discover/movie", .movie)
                let today = Date.now
                let end = Calendar(identifier: .gregorian).date(byAdding: .month, value: 6, to: today) ?? today
                parameters["primary_release_date.gt"] = Self.day(today)
                parameters["primary_release_date.lte"] = Self.day(end)
                parameters["sort_by"] = "popularity.desc"
            case .topRated:
                async let movies = results("movie/top_rated", kind: .movie, page: page, language: language)
                async let series = results("tv/top_rated", kind: .tv, page: page, language: language)
                return try await .combined(movies, series)
            }
            return try await results(path, kind: kind, page: page, language: language, parameters: parameters)
        case .discover(let filter):
            if let kind = filter.kind {
                return try await discover(filter, kind: kind, page: page, language: language)
            }
            async let movies = discover(filter, kind: .movie, page: page, language: language)
            async let series = discover(filter, kind: .tv, page: page, language: language)
            return try await .combined(movies, series)
        case .search(let query, let filter):
            var parameters = ["query": query]
            if let year = filter.year, let kind = filter.kind {
                parameters[kind == .movie ? "primary_release_year" : "first_air_date_year"] = String(year)
            }
            return try await results(
                "search/\(filter.kind?.rawValue ?? "multi")", kind: filter.kind,
                page: page, language: language, parameters: parameters
            ).filtered(by: filter)
        }
    }

    func genres(kind: MediaKind, language: String) async throws -> [CatalogGenre] {
        let envelope: GenreResponse = try await tmdb.request(
            path: "genre/\(kind.rawValue)/list", queryItems: [URLQueryItem(name: "language", value: language)]
        )
        return envelope.genres
    }

    func details(for identity: CatalogIdentity, language: String) async throws -> CatalogDetails {
        let response: DetailsResponse = try await tmdb.request(
            path: "\(identity.kind.rawValue)/\(identity.tmdbID)",
            queryItems: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "append_to_response", value: "credits,videos,similar,recommendations"),
                URLQueryItem(name: "include_video_language", value: language.hasPrefix("ru") ? "ru,en" : "en")
            ]
        )
        guard let item = response.item.item(kind: identity.kind), item.id == identity else {
            throw MetadataServiceError.invalidResponse
        }
        let trailer = response.videos?.results.filter { $0.site == "YouTube" && $0.type == "Trailer" }
            .first { $0.key.count == 11 && $0.key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) } }
        let related = (response.similar?.results ?? []) + (response.recommendations?.results ?? [])
        var seen: Set<CatalogIdentity> = [identity]
        return CatalogDetails(
            item: item, genres: response.genres, runtime: response.runtime ?? response.episodeRunTime?.first,
            cast: Array((response.credits?.cast ?? []).prefix(12)),
            trailer: trailer.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") },
            similar: Array(related.compactMap { $0.item(kind: identity.kind) }
                .filter { seen.insert($0.id).inserted }.prefix(20)),
            seasons: (response.seasons ?? []).sorted { $0.seasonNumber < $1.seasonNumber }
        )
    }

    private func discover(_ filter: CatalogFilter, kind: MediaKind, page: Int, language: String) async throws -> CatalogPage {
        var parameters = ["sort_by": "popularity.desc"]
        if let genre = filter.genreID { parameters["with_genres"] = String(genre) }
        if let year = filter.year {
            parameters[kind == .movie ? "primary_release_year" : "first_air_date_year"] = String(year)
        }
        if let rating = filter.minimumRating { parameters["vote_average.gte"] = String(rating) }
        return try await results("discover/\(kind.rawValue)", kind: kind, page: page, language: language, parameters: parameters)
    }

    private func results(
        _ path: String, kind: MediaKind?, page: Int, language: String, parameters: [String: String] = [:]
    ) async throws -> CatalogPage {
        var query = parameters
        query["page"] = String(page)
        query["language"] = language
        query["include_adult"] = "false"
        let response: CatalogResponse = try await tmdb.request(
            path: path, queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        )
        return try response.page(page, kind: kind)
    }

    static func day(_ date: Date) -> String {
        String(date.ISO8601Format().prefix(10))
    }
}

private struct GenreResponse: Decodable {
    let genres: [CatalogGenre]
}

private struct DetailsResponse: Decodable {
    struct Credits: Decodable { let cast: [CatalogCastMember] }
    struct Videos: Decodable {
        struct Video: Decodable {
            let site: String
            let type: String
            let key: String
        }
        let results: [Video]
    }

    let item: CatalogItemResponse
    let genres: [CatalogGenre]
    let runtime: Int?
    let episodeRunTime: [Int]?
    let credits: Credits?
    let videos: Videos?
    let similar: CatalogResponse?
    let recommendations: CatalogResponse?
    let seasons: [CatalogSeason]?

    private enum CodingKeys: String, CodingKey {
        case genres, runtime, episodeRunTime, credits, videos, similar, recommendations, seasons
    }

    init(from decoder: Decoder) throws {
        item = try CatalogItemResponse(from: decoder)
        let data = try decoder.container(keyedBy: CodingKeys.self)
        genres = try data.decodeIfPresent([CatalogGenre].self, forKey: .genres) ?? []
        runtime = try data.decodeIfPresent(Int.self, forKey: .runtime)
        episodeRunTime = try data.decodeIfPresent([Int].self, forKey: .episodeRunTime)
        credits = try data.decodeIfPresent(Credits.self, forKey: .credits)
        videos = try data.decodeIfPresent(Videos.self, forKey: .videos)
        similar = try data.decodeIfPresent(CatalogResponse.self, forKey: .similar)
        recommendations = try data.decodeIfPresent(CatalogResponse.self, forKey: .recommendations)
        seasons = try data.decodeIfPresent([CatalogSeason].self, forKey: .seasons)
    }
}

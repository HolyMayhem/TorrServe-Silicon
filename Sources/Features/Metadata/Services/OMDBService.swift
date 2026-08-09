import Foundation

final class OMDBService: MetadataServicing, @unchecked Sendable {
    let provider = MetadataProvider.omdb

    private let configurationProvider: OMDBConfigurationProviding
    private let session: URLSession

    init(
        configurationProvider: OMDBConfigurationProviding = MetadataSettingsStore.shared,
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
            URLQueryItem(name: "s", value: title),
            URLQueryItem(name: "type", value: kind == .movie ? "movie" : "series"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "r", value: "json")
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "y", value: String(year)))
        }

        let response: OMDBSearchResponse = try await request(queryItems: queryItems)
        guard response.succeeded else {
            if response.error?.localizedCaseInsensitiveContains("not found") == true {
                return []
            }
            throw MetadataServiceError.api(response.error ?? "OMDb search failed.")
        }

        return (response.results ?? []).map { result in
            MediaSearchResult(
                id: result.imdbID,
                provider: .omdb,
                kind: result.type.mediaKind ?? kind,
                localizedTitle: result.title,
                originalTitle: result.title,
                releaseDate: result.year.normalizedValue,
                posterURL: result.poster.remoteURL,
                backdropURL: nil,
                overview: "",
                rating: 0,
                popularity: 0
            )
        }
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        let response: OMDBDetailsResponse = try await request(queryItems: [
            URLQueryItem(name: "i", value: id),
            URLQueryItem(name: "plot", value: "full"),
            URLQueryItem(name: "r", value: "json")
        ])
        guard response.succeeded else {
            throw MetadataServiceError.api(response.error ?? "OMDb details request failed.")
        }

        return MediaMetadata(
            id: response.imdbID ?? id,
            provider: .omdb,
            kind: response.type?.mediaKind ?? kind,
            localizedTitle: response.title.normalizedValue ?? "",
            originalTitle: response.title.normalizedValue ?? "",
            overview: response.plot.normalizedValue ?? "",
            genres: response.genre.normalizedValue?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? [],
            runtimeMinutes: response.runtime.flatMap(Self.runtimeMinutes),
            releaseDate: response.released.normalizedValue ?? response.year.normalizedValue,
            rating: response.imdbRating.flatMap(Double.init) ?? 0,
            posterURL: response.poster.remoteURL,
            backdropURL: nil
        )
    }

    private func request<Response: Decodable>(
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard let configuration = configurationProvider.omdbConfiguration() else {
            throw MetadataServiceError.notConfigured(.omdb)
        }

        var components = URLComponents(
            url: configuration.apiBaseURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems + [
            URLQueryItem(name: "apikey", value: configuration.apiKey)
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
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed
        }
    }

    private static func runtimeMinutes(_ value: String) -> Int? {
        value
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first(where: { !$0.isEmpty })
            .flatMap(Int.init)
    }
}

private struct OMDBSearchResponse: Decodable {
    let results: [OMDBSearchItem]?
    let response: String
    let error: String?

    var succeeded: Bool { response.caseInsensitiveCompare("True") == .orderedSame }

    private enum CodingKeys: String, CodingKey {
        case results = "Search"
        case response = "Response"
        case error = "Error"
    }
}

private struct OMDBSearchItem: Decodable {
    let title: String
    let year: String
    let imdbID: String
    let type: String
    let poster: String

    private enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case imdbID
        case type = "Type"
        case poster = "Poster"
    }
}

private struct OMDBDetailsResponse: Decodable {
    let title: String?
    let year: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let plot: String?
    let poster: String?
    let imdbRating: String?
    let imdbID: String?
    let type: String?
    let response: String
    let error: String?

    var succeeded: Bool { response.caseInsensitiveCompare("True") == .orderedSame }

    private enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case released = "Released"
        case runtime = "Runtime"
        case genre = "Genre"
        case plot = "Plot"
        case poster = "Poster"
        case imdbRating
        case imdbID
        case type = "Type"
        case response = "Response"
        case error = "Error"
    }
}

private extension Optional where Wrapped == String {
    var normalizedValue: String? {
        guard let self else { return nil }
        return self.normalizedValue
    }

    var remoteURL: URL? {
        normalizedValue.flatMap(URL.init(string:))
    }
}

private extension String {
    var normalizedValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.caseInsensitiveCompare("N/A") != .orderedSame else {
            return nil
        }
        return value
    }

    var remoteURL: URL? {
        normalizedValue.flatMap(URL.init(string:))
    }

    var mediaKind: MediaKind? {
        switch lowercased() {
        case "movie": return .movie
        case "series", "episode": return .tv
        default: return nil
        }
    }
}

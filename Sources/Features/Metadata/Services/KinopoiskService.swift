import Foundation

final class KinopoiskService: MetadataServicing, @unchecked Sendable {
    let provider = MetadataProvider.kinopoisk

    private let configurationProvider: KinopoiskConfigurationProviding
    private let session: URLSession

    init(
        configurationProvider: KinopoiskConfigurationProviding = MetadataSettingsStore.shared,
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
            URLQueryItem(name: "keyword", value: title),
            URLQueryItem(name: "page", value: "1")
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "yearFrom", value: String(year)))
            queryItems.append(URLQueryItem(name: "yearTo", value: String(year)))
        }

        let response: KinopoiskSearchResponse = try await request(
            path: "api/v2.2/films",
            queryItems: queryItems
        )
        return response.items.map { $0.result(language: language, fallbackKind: kind) }
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        guard Int(id) != nil else { throw MetadataServiceError.invalidRequest }
        let response: KinopoiskFilmResponse = try await request(
            path: "api/v2.2/films/\(id)",
            queryItems: []
        )
        return response.metadata(language: language, fallbackKind: kind)
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard let configuration = configurationProvider.kinopoiskConfiguration() else {
            throw MetadataServiceError.notConfigured(.kinopoisk)
        }

        var components = URLComponents(
            url: configuration.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw MetadataServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-KEY")

        let data = try await MetadataHTTPTransport.data(for: request, session: session)
        return try MetadataHTTPTransport.decode(Response.self, from: data)
    }
}

private struct KinopoiskSearchResponse: Decodable {
    let items: [KinopoiskSearchItem]
}

private struct KinopoiskSearchItem: Decodable {
    let kinopoiskId: Int
    let nameRu: String?
    let nameEn: String?
    let nameOriginal: String?
    let ratingKinopoisk: Double?
    let ratingImdb: Double?
    let year: Int?
    let type: String?
    let posterUrl: String?

    func result(language: String, fallbackKind: MediaKind) -> MediaSearchResult {
        MediaSearchResult(
            id: String(kinopoiskId),
            provider: .kinopoisk,
            kind: type?.kinopoiskMediaKind ?? fallbackKind,
            localizedTitle: localizedTitle(language: language),
            originalTitle: nameOriginal.normalizedValue
                ?? nameEn.normalizedValue
                ?? nameRu.normalizedValue
                ?? "",
            releaseDate: year.map(String.init),
            posterURL: posterUrl.remoteURL,
            backdropURL: nil,
            overview: "",
            rating: ratingKinopoisk ?? ratingImdb ?? 0,
            popularity: ratingKinopoisk ?? ratingImdb ?? 0
        )
    }

    private func localizedTitle(language: String) -> String {
        if language.hasPrefix("ru") {
            return nameRu.normalizedValue
                ?? nameEn.normalizedValue
                ?? nameOriginal.normalizedValue
                ?? ""
        }
        return nameEn.normalizedValue
            ?? nameOriginal.normalizedValue
            ?? nameRu.normalizedValue
            ?? ""
    }
}

private struct KinopoiskFilmResponse: Decodable {
    let kinopoiskId: Int
    let nameRu: String?
    let nameEn: String?
    let nameOriginal: String?
    let posterUrl: String?
    let coverUrl: String?
    let ratingKinopoisk: Double?
    let ratingImdb: Double?
    let year: Int?
    let filmLength: Int?
    let description: String?
    let shortDescription: String?
    let type: String?
    let genres: [KinopoiskGenre]

    func metadata(language: String, fallbackKind: MediaKind) -> MediaMetadata {
        MediaMetadata(
            id: String(kinopoiskId),
            provider: .kinopoisk,
            kind: type?.kinopoiskMediaKind ?? fallbackKind,
            localizedTitle: localizedTitle(language: language),
            originalTitle: nameOriginal.normalizedValue
                ?? nameEn.normalizedValue
                ?? nameRu.normalizedValue
                ?? "",
            overview: description.normalizedValue ?? shortDescription.normalizedValue ?? "",
            genres: genres.map(\.genre),
            runtimeMinutes: filmLength,
            releaseDate: year.map(String.init),
            rating: ratingKinopoisk ?? ratingImdb ?? 0,
            posterURL: posterUrl.remoteURL,
            backdropURL: coverUrl.remoteURL
        )
    }

    private func localizedTitle(language: String) -> String {
        if language.hasPrefix("ru") {
            return nameRu.normalizedValue
                ?? nameEn.normalizedValue
                ?? nameOriginal.normalizedValue
                ?? ""
        }
        return nameEn.normalizedValue
            ?? nameOriginal.normalizedValue
            ?? nameRu.normalizedValue
            ?? ""
    }
}

private struct KinopoiskGenre: Decodable {
    let genre: String
}

private extension Optional where Wrapped == String {
    var normalizedValue: String? {
        guard let value = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var remoteURL: URL? {
        normalizedValue.flatMap(URL.init(string:))
    }
}

private extension String {
    var kinopoiskMediaKind: MediaKind? {
        switch uppercased() {
        case "FILM", "VIDEO": return .movie
        case "TV_SHOW", "TV_SERIES", "MINI_SERIES": return .tv
        default: return nil
        }
    }
}

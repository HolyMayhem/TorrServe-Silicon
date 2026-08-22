import Foundation

final class AniListService: MetadataServicing, @unchecked Sendable {
    let provider = MetadataProvider.anilist

    private static let searchQuery = """
    query SearchAnime($search: String!) {
      Page(page: 1, perPage: 10) {
        media(search: $search, type: ANIME, isAdult: false) {
          id
          title { romaji english native }
          synonyms
          format
          description(asHtml: false)
          startDate { year month day }
          duration
          coverImage { extraLarge large medium }
          bannerImage
          genres
          averageScore
          popularity
        }
      }
    }
    """

    private static let detailsQuery = """
    query AnimeDetails($id: Int!) {
      Media(id: $id, type: ANIME) {
        id
        title { romaji english native }
        synonyms
        format
        description(asHtml: false)
        startDate { year month day }
        duration
        coverImage { extraLarge large medium }
        bannerImage
        genres
        averageScore
        popularity
      }
    }
    """

    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://graphql.anilist.co")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func search(
        title: String,
        year: Int?,
        kind: MediaKind,
        language: String
    ) async throws -> [MediaSearchResult] {
        let data: AniListSearchData = try await request(
            query: Self.searchQuery,
            variables: AniListSearchVariables(search: title)
        )
        return data.page.media.map { media in
            MediaSearchResult(
                id: String(media.id),
                provider: .anilist,
                kind: media.mediaKind,
                localizedTitle: media.bestMatchingTitle(for: title, language: language),
                originalTitle: media.title.romaji
                    ?? media.title.native
                    ?? media.title.english
                    ?? title,
                releaseDate: media.startDate?.formatted,
                posterURL: media.coverImage?.bestURL,
                backdropURL: media.bannerImage,
                overview: media.description.aniListPlainText,
                rating: Double(media.averageScore ?? 0) / 10,
                popularity: Double(media.popularity ?? 0)
            )
        }
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        guard let mediaID = Int(id) else { throw MetadataServiceError.invalidRequest }
        let data: AniListDetailsData = try await request(
            query: Self.detailsQuery,
            variables: AniListDetailsVariables(id: mediaID)
        )
        let media = data.media
        return MediaMetadata(
            id: String(media.id),
            provider: .anilist,
            kind: media.mediaKind,
            localizedTitle: media.preferredTitle(language: language),
            originalTitle: media.title.romaji
                ?? media.title.native
                ?? media.title.english
                ?? "",
            overview: media.description.aniListPlainText,
            genres: media.genres,
            runtimeMinutes: media.duration,
            releaseDate: media.startDate?.formatted,
            rating: Double(media.averageScore ?? 0) / 10,
            posterURL: media.coverImage?.bestURL,
            backdropURL: media.bannerImage
        )
    }

    private func request<Variables: Encodable, Response: Decodable>(
        query: String,
        variables: Variables
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TorrServe macOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            AniListGraphQLRequest(query: query, variables: variables)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MetadataServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw MetadataServiceError.httpStatus(http.statusCode)
        }

        let envelope: AniListGraphQLEnvelope<Response>
        do {
            envelope = try JSONDecoder().decode(AniListGraphQLEnvelope<Response>.self, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed
        }
        if let value = envelope.data {
            return value
        }
        throw MetadataServiceError.api(
            envelope.errors?.first?.message ?? "AniList returned an empty response."
        )
    }
}

private struct AniListGraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct AniListGraphQLEnvelope<Response: Decodable>: Decodable {
    let data: Response?
    let errors: [AniListGraphQLError]?
}

private struct AniListGraphQLError: Decodable {
    let message: String
}

private struct AniListSearchVariables: Encodable {
    let search: String
}

private struct AniListDetailsVariables: Encodable {
    let id: Int
}

private struct AniListSearchData: Decodable {
    let page: AniListMediaPage

    private enum CodingKeys: String, CodingKey {
        case page = "Page"
    }
}

private struct AniListDetailsData: Decodable {
    let media: AniListMedia

    private enum CodingKeys: String, CodingKey {
        case media = "Media"
    }
}

private struct AniListMediaPage: Decodable {
    let media: [AniListMedia]
}

private struct AniListMedia: Decodable {
    let id: Int
    let title: AniListMediaTitle
    let synonyms: [String]
    let format: String?
    let description: String?
    let startDate: AniListFuzzyDate?
    let duration: Int?
    let coverImage: AniListCoverImage?
    let bannerImage: URL?
    let genres: [String]
    let averageScore: Int?
    let popularity: Int?

    var mediaKind: MediaKind {
        format == "MOVIE" ? .movie : .tv
    }

    func preferredTitle(language: String) -> String {
        if language.hasPrefix("en") || language.hasPrefix("ru") {
            return title.english ?? title.romaji ?? title.native ?? ""
        }
        return title.romaji ?? title.english ?? title.native ?? ""
    }

    func bestMatchingTitle(for query: String, language: String) -> String {
        let values = [title.english, title.romaji, title.native]
            .compactMap { $0 } + synonyms
        let normalizedQuery = query.aniListNormalizedTitle
        if let exact = values.first(where: {
            $0.aniListNormalizedTitle == normalizedQuery
        }) {
            return exact
        }
        if let partial = values.first(where: {
            let value = $0.aniListNormalizedTitle
            return value.contains(normalizedQuery) || normalizedQuery.contains(value)
        }) {
            return partial
        }
        return preferredTitle(language: language)
    }
}

private struct AniListMediaTitle: Decodable {
    let romaji: String?
    let english: String?
    let native: String?
}

private struct AniListFuzzyDate: Decodable {
    let year: Int?
    let month: Int?
    let day: Int?

    var formatted: String? {
        guard let year else { return nil }
        guard let month else { return String(format: "%04d", year) }
        guard let day else { return String(format: "%04d-%02d", year, month) }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private struct AniListCoverImage: Decodable {
    let extraLarge: URL?
    let large: URL?
    let medium: URL?

    var bestURL: URL? {
        extraLarge ?? large ?? medium
    }
}

private extension Optional where Wrapped == String {
    var aniListPlainText: String {
        self?.aniListPlainText ?? ""
    }
}

private extension String {
    var aniListNormalizedTitle: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var aniListPlainText: String {
        replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"[*_~]{1,2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

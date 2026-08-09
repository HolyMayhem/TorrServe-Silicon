import Foundation

enum MetadataProvider: String, Codable, CaseIterable, Sendable {
    case tmdb
    case omdb

    var displayName: String {
        switch self {
        case .tmdb: return "TMDB"
        case .omdb: return "OMDb"
        }
    }

    func sourceURL(id: String, kind: MediaKind) -> URL? {
        switch self {
        case .tmdb:
            return URL(string: "https://www.themoviedb.org/\(kind.rawValue)/\(id)")
        case .omdb:
            return URL(string: "https://www.imdb.com/title/\(id)")
        }
    }
}

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case movie
    case tv
}

struct ParsedMediaName: Equatable, Sendable {
    let title: String
    let year: Int?
    let kind: MediaKind
    let season: Int?
    let episode: Int?
}

struct MediaTitleCandidate: Equatable, Sendable {
    let parsedName: ParsedMediaName
    let confidence: Int
}

struct MediaSearchResult: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: MetadataProvider
    let kind: MediaKind
    let localizedTitle: String
    let originalTitle: String
    let releaseDate: String?
    let posterURL: URL?
    let backdropURL: URL?
    let overview: String
    let rating: Double
    let popularity: Double

    var releaseYear: Int? {
        guard let releaseDate else { return nil }
        return releaseDate
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first { value in
                guard value.count == 4, let year = Int(value) else { return false }
                return (1900...2099).contains(year)
            }
            .flatMap(Int.init)
    }
}

struct MediaMetadata: Codable, Equatable, Sendable {
    let id: String
    let provider: MetadataProvider
    let kind: MediaKind
    let localizedTitle: String
    let originalTitle: String
    let overview: String
    let genres: [String]
    let runtimeMinutes: Int?
    let releaseDate: String?
    let rating: Double
    let posterURL: URL?
    let backdropURL: URL?
}

struct ResolvedMediaMetadata: Equatable, Sendable {
    let parsedName: ParsedMediaName
    let metadata: MediaMetadata
}

enum MetadataResolutionOutcome: Equatable, Sendable {
    case resolved(ResolvedMediaMetadata)
    case notFound
    case unavailable
}

enum MetadataServiceError: LocalizedError, Equatable {
    case notConfigured(MetadataProvider)
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "\(provider.displayName) API key is not configured."
        case .invalidRequest:
            return "Could not create the metadata request."
        case .invalidResponse:
            return "The metadata provider returned an invalid response."
        case .httpStatus(let status):
            return "The metadata provider returned HTTP \(status)."
        case .decodingFailed:
            return "Could not decode the metadata response."
        case .api(let message):
            return message
        }
    }
}

protocol MetadataServicing: Sendable {
    var provider: MetadataProvider { get }

    func search(
        title: String,
        year: Int?,
        kind: MediaKind,
        language: String
    ) async throws -> [MediaSearchResult]

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata
}

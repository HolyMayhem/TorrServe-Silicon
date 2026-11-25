import Foundation

enum CatalogSource: String, CaseIterable, Codable, Sendable {
    case tmdb
    case cub
    case auto
}

enum CatalogCollection: String, CaseIterable, Hashable, Sendable {
    case trending
    case newMovies
    case popularMovies
    case popularTV
    case upcoming
    case topRated
}

struct CatalogIdentity: Hashable, Codable, Sendable {
    let kind: MediaKind
    let tmdbID: Int
}

struct CatalogItem: Identifiable, Hashable, Codable, Sendable {
    let id: CatalogIdentity
    let title: String
    let originalTitle: String
    let overview: String
    let date: String?
    let rating: Double
    let poster: URL?
    let backdrop: URL?
    let genreIDs: [Int]

    var year: Int? { date.flatMap { Int($0.prefix(4)) } }
}

struct CatalogGenre: Identifiable, Equatable, Codable, Sendable {
    let id: Int
    let name: String
}

struct CatalogFilter: Hashable, Sendable {
    var kind: MediaKind? = nil
    var genreID: Int? = nil
    var year: Int? = nil
    var minimumRating: Int? = nil

    func includes(_ item: CatalogItem) -> Bool {
        (kind == nil || item.id.kind == kind)
            && (genreID.map { item.genreIDs.contains($0) } ?? true)
            && (year == nil || item.year == year)
            && (minimumRating.map { item.rating >= Double($0) } ?? true)
    }
}

enum CatalogListing: Hashable, Sendable {
    case collection(CatalogCollection)
    case discover(CatalogFilter)
    case search(String, CatalogFilter)
}

struct CatalogPage: Codable, Sendable {
    let items: [CatalogItem]
    let number: Int
    let totalPages: Int
}

enum CatalogImageURL {
    static func make(_ path: String?, size: String) -> URL? {
        guard let path, path.hasPrefix("/"),
              !path.dropFirst().contains("/"),
              path.dropFirst().allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
              path.count > 1, !path.contains("..") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

struct CatalogCastMember: Decodable, Sendable {
    let name: String
    let character: String?
    let profilePath: String?

    var portrait: URL? { CatalogImageURL.make(profilePath, size: "w185") }
}

struct CatalogSeason: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int?
    let airDate: String?
}

struct CatalogDetails: Sendable {
    let item: CatalogItem
    let genres: [CatalogGenre]
    let runtime: Int?
    let cast: [CatalogCastMember]
    let trailer: URL?
    let similar: [CatalogItem]
    let seasons: [CatalogSeason]
}

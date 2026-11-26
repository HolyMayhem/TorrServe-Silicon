import Foundation

struct CatalogResponse: Decodable {
    let results: [CatalogItemResponse]
    let totalPages: Int
    let success: Bool?
    let secuses: Bool?
    let statusCode: Int?

    func page(_ number: Int, kind: MediaKind? = nil) throws -> CatalogPage {
        guard success != false, secuses != false, (statusCode ?? 0) == 0 else {
            throw MetadataServiceError.invalidResponse
        }
        var seen = Set<CatalogIdentity>()
        let items = results.compactMap { $0.item(kind: kind) }.filter { seen.insert($0.id).inserted }
        return CatalogPage(items: items, number: number, totalPages: max(0, min(totalPages, 500)))
    }
}

struct CatalogItemResponse: Decodable {
    let id: Int?
    let mediaType: String?
    let adult: Bool?
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let genreIds: [Int]?

    func item(kind: MediaKind?) -> CatalogItem? {
        guard let id, id > 0, adult != true,
              let type = kind ?? mediaType.flatMap(MediaKind.init(rawValue:)) else { return nil }
        let original = type == .movie ? originalTitle : originalName ?? originalTitle
        let preferred = type == .movie ? title : name ?? title
        let displayTitle = [preferred, original].compactMap { $0 }.first { !$0.isEmpty }
        guard let displayTitle else { return nil }
        return CatalogItem(
            id: CatalogIdentity(kind: type, tmdbID: id), title: displayTitle,
            originalTitle: original ?? "", overview: overview ?? "",
            date: type == .movie ? releaseDate : firstAirDate ?? releaseDate,
            rating: min(10, max(0, voteAverage ?? 0)),
            poster: CatalogImageURL.make(posterPath, size: "w342"),
            backdrop: CatalogImageURL.make(backdropPath, size: "w780"),
            genreIDs: genreIds ?? []
        )
    }
}

extension CatalogPage {
    static func combined(_ first: CatalogPage, _ second: CatalogPage) -> CatalogPage {
        var items: [CatalogItem] = []
        for index in 0..<max(first.items.count, second.items.count) {
            if index < first.items.count { items.append(first.items[index]) }
            if index < second.items.count { items.append(second.items[index]) }
        }
        return CatalogPage(items: items, number: first.number, totalPages: max(first.totalPages, second.totalPages))
    }

    func filtered(by filter: CatalogFilter) -> CatalogPage {
        CatalogPage(items: items.filter(filter.includes), number: number, totalPages: totalPages)
    }
}

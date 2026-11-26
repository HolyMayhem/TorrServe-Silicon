import Foundation

struct CatalogTorrentContext {
    let item: CatalogItem
    let details: CatalogDetails?

    var queries: [String] {
        let title = details?.item.title ?? item.title
        let original = [details?.item.originalTitle, item.originalTitle]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let year = details?.item.year ?? item.year
        var queries: [String] = []
        for name in [title, original, item.title] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let query = year.map { "\(trimmed) \($0)" } ?? trimmed
            if !queries.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
                queries.append(query)
            }
        }
        return queries
    }
}

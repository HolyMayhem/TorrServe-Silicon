import Foundation

struct CatalogConnection: Hashable, Sendable {
    static let publicCUB = URL(string: "https://tmdb.cub.best/")!

    var source: CatalogSource = .tmdb
    var cubURL: URL = Self.publicCUB
    var cubToken = ""
    var timeout = 12.0

    static func endpoint(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 2048, let parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            return nil
        }
        return parts.url
    }
}

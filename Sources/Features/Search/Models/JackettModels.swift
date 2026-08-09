import Foundation

struct JackettConfiguration: Equatable {
    var serverURL: String
    var apiKey: String

    var normalizedServerURL: URL? {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        guard
            let url = URL(string: value),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    var isComplete: Bool {
        normalizedServerURL != nil
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct JackettSearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let tracker: String
    let downloadURL: URL?
    let magnetURL: URL?
    let posterURL: URL?
    let detailsURL: URL?
    let size: Int64
    let seeders: Int
    let peers: Int
    let categories: [String]
    let publishedAt: Date?
    let infoHash: String
    let year: String

    var bestDownloadURL: URL? {
        magnetURL ?? downloadURL
    }

    var torrServerCategory: String {
        if categories.contains(where: { $0.hasPrefix("2") }) {
            return "movie"
        }
        if categories.contains(where: { $0.hasPrefix("5") }) {
            return "tv"
        }
        return "other"
    }
}

enum JackettDownloadPayload {
    case magnet(String)
    case torrent(data: Data, filename: String)
}

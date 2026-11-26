import Foundation

struct JackettConfiguration: Equatable, Sendable {
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

enum TorrentSearchLinkSource: String, Sendable {
    case jackett = "Jackett"
    case torrentSearch = "TorrentSearch"
}

struct JackettSearchResult: Identifiable, Equatable, Sendable {
    var id: String
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
    var downloadSource: TorrentSearchLinkSource = .torrentSearch
    var magnetSource: TorrentSearchLinkSource = .torrentSearch

    var preferredLinkSource: TorrentSearchLinkSource {
        magnetURL == nil ? downloadSource : magnetSource
    }

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

enum JackettDownloadPayload: Sendable {
    case magnet(String)
    case torrent(data: Data, filename: String)

    var kind: String {
        switch self {
        case .magnet: return "magnet"
        case .torrent: return "torrent"
        }
    }
}

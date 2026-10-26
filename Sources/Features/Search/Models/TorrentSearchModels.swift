import Foundation

enum TorrentSearchMode: String, CaseIterable, Identifiable, Sendable {
    case torrentSearch, jackett, combined
    var id: Self { self }
    var usesTorrentSearch: Bool { self != .jackett }
    var usesJackett: Bool { self != .torrentSearch }

    func title(language: AppLanguage) -> String {
        switch self {
        case .torrentSearch: return "TorrentSearch"
        case .jackett: return "Jackett"
        case .combined: return language == .russian ? "Все источники" : "All Sources"
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .torrentSearch:
            return language == .russian ? "Встроенный поиск по открытым источникам. Адрес сервера и API-ключ не нужны." : "Built-in search across public sources. No server address or API key required."
        case .jackett:
            return language == .russian ? "Поиск по индексаторам вашего сервера Jackett." : "Search the indexers on your Jackett server."
        case .combined:
            return language == .russian ? "TorrentSearch и Jackett в одном списке. Одинаковые раздачи объединяются." : "TorrentSearch and Jackett in one list. Duplicate torrents are merged."
        }
    }
}

enum TorrentSearchProvider: String, CaseIterable, Identifiable, Sendable {
    case knaben, torrentsCSV, rutor, nyaa, yts
    var id: Self { self }
    var title: String {
        switch self {
        case .knaben: return "Knaben"
        case .torrentsCSV: return "TorrentsCSV"
        case .rutor: return "Rutor"
        case .nyaa: return "Nyaa"
        case .yts: return "YTS"
        }
    }
    var siteURL: URL {
        switch self {
        case .knaben: return URL(string: "https://knaben.org")!
        case .torrentsCSV: return URL(string: "https://torrents-csv.com")!
        case .rutor: return URL(string: "https://rutor.info")!
        case .nyaa: return URL(string: "https://nyaa.si")!
        case .yts: return URL(string: "https://yts.bz")!
        }
    }
    func detail(language: AppLanguage) -> String {
        switch self {
        case .knaben: return language == .russian ? "Общий поиск по нескольким индексам" : "General search across multiple indexes"
        case .torrentsCSV: return language == .russian ? "Открытый каталог раздач" : "Open torrent catalogue"
        case .rutor: return language == .russian ? "Русскоязычные раздачи" : "Russian-language releases"
        case .nyaa: return language == .russian ? "Аниме и азиатские сериалы" : "Anime and Asian series"
        case .yts: return language == .russian ? "Фильмы с вариантами качества" : "Movies in multiple qualities"
        }
    }
}

struct TorrentSearchSourceOutcome: Sendable {
    let name: String
    let results: [JackettSearchResult]
    let error: String?
}

protocol TorrentSearchServing: Sendable {
    func search(query: String, provider: TorrentSearchProvider) async throws -> [JackettSearchResult]
}

enum TorrentSearchIdentity {
    static func normalizedHash(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.count == 40, value.allSatisfy({ $0.isASCII && $0.isHexDigit }), value.contains(where: { $0 != "0" }) {
            return value
        }
        // BTIH may be encoded as base32 in magnets, while APIs return hex.
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        guard value.count == 32 else { return nil }
        var buffer: UInt32 = 0
        var bits = 0
        var bytes: [UInt8] = []
        for character in value {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | UInt32(digit)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 0xff))
                buffer &= (1 << bits) - 1
            }
        }
        guard bytes.count == 20, bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(in magnet: URL?) -> String? {
        guard let magnet, magnet.scheme?.lowercased() == "magnet",
              let components = URLComponents(url: magnet, resolvingAgainstBaseURL: false) else { return nil }
        for item in components.queryItems ?? [] where item.name.lowercased() == "xt" {
            guard let value = item.value, value.lowercased().hasPrefix("urn:btih:") else { continue }
            if let hash = normalizedHash(String(value.dropFirst("urn:btih:".count))) { return hash }
        }
        return nil
    }

    static func magnet(hash: String, title: String) -> URL? {
        guard let hash = normalizedHash(hash) else { return nil }
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [URLQueryItem(name: "xt", value: "urn:btih:\(hash)"), URLQueryItem(name: "dn", value: title)]
            + ["udp://tracker.opentrackr.org:1337/announce", "udp://open.demonii.com:1337/announce", "udp://tracker.torrent.eu.org:451/announce"].map { URLQueryItem(name: "tr", value: $0) }
        return components.url
    }

    static func merge(_ results: [JackettSearchResult]) -> [JackettSearchResult] {
        var values: [JackettSearchResult] = []
        var indexes: [String: Int] = [:]
        for result in results {
            let hash = hash(in: result.magnetURL) ?? normalizedHash(result.infoHash)
            let key = hash.map { "btih:\($0)" } ?? result.bestDownloadURL?.absoluteString ?? result.id
            guard let index = indexes[key] else {
                indexes[key] = values.count
                var canonical = result
                if hash != nil { canonical.id = key }
                values.append(canonical)
                continue
            }
            let old = values[index]
            let best = result.seeders > old.seeders ? result : old
            let other = result.seeders > old.seeders ? old : result
            let sources = Set((old.tracker + ", " + result.tracker).components(separatedBy: ", ").filter { !$0.isEmpty }).sorted().joined(separator: ", ")
            values[index] = JackettSearchResult(
                id: old.id, title: best.title,
                summary: best.summary.isEmpty ? other.summary : best.summary,
                tracker: sources, downloadURL: best.downloadURL ?? other.downloadURL,
                magnetURL: best.magnetURL ?? other.magnetURL,
                posterURL: best.posterURL ?? other.posterURL, detailsURL: best.detailsURL ?? other.detailsURL,
                size: best.size > 0 ? best.size : other.size, seeders: max(old.seeders, result.seeders),
                peers: max(old.peers, result.peers), categories: Array(Set(old.categories + result.categories)).sorted(),
                publishedAt: best.publishedAt ?? other.publishedAt, infoHash: hash ?? best.infoHash,
                year: best.year.isEmpty ? other.year : best.year
            )
        }
        return values
    }
}

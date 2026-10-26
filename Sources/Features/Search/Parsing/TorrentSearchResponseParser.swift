import Foundation

/// Response mappings ported from TorrentSearch providers; MIT attribution is bundled.
enum TorrentSearchResponseParser {
    static func parse(_ data: Data, provider: TorrentSearchProvider, pageURL: URL) throws -> [JackettSearchResult] {
        if provider == .rutor || provider == .nyaa { return try parseHTML(data, provider: provider, pageURL: pageURL) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalidResponse }
        switch provider {
        case .knaben:
            guard let hits = root["hits"] as? [[String: Any]] else { throw invalidResponse }
            return hits.compactMap { item in
                let categories = item["categoryId"] as? [NSNumber] ?? []
                let category: [String]
                if categories.contains(where: { (2_000_000..<3_000_000).contains($0.intValue) }) { category = ["5000"] }
                else if categories.contains(where: { (3_000_000..<4_000_000).contains($0.intValue) }) { category = ["2000"] }
                else { category = [] }
                return makeResult(provider: provider, title: text(item["title"]), hash: text(item["hash"]),
                    magnet: webURL(item["magnetUrl"], allowMagnet: true), size: number(item["bytes"]),
                    seeders: number(item["seeders"]), peers: number(item["peers"]),
                    date: isoDate(text(item["date"])), categories: category, details: webURL(item["details"]),
                    summary: text(item["description"]))
            }
        case .torrentsCSV:
            guard let hits = root["torrents"] as? [[String: Any]] else { throw invalidResponse }
            return hits.compactMap { item in
                makeResult(provider: provider, title: text(item["name"]), hash: text(item["infohash"]),
                    size: number(item["size_bytes"]), seeders: number(item["seeders"]), peers: number(item["leechers"]),
                    date: epochDate(item["created_unix"]))
            }
        case .yts:
            guard text(root["status"]) == "ok", let body = root["data"] as? [String: Any] else { throw invalidResponse }
            if number(body["movie_count"]) == 0, body["movies"] == nil { return [] }
            guard let movies = body["movies"] as? [[String: Any]] else { throw invalidResponse }
            return movies.flatMap { movie -> [JackettSearchResult] in
                let title = text(movie["title_long"]).isEmpty ? text(movie["title"]) : text(movie["title_long"])
                return (movie["torrents"] as? [[String: Any]] ?? []).compactMap { torrent in
                    let format = ["quality", "type", "video_codec"].compactMap { key -> String? in
                        let value = text(torrent[key]); return value.isEmpty ? nil : "[\(value)]"
                    }.joined(separator: " ")
                    return makeResult(provider: provider, title: title + (format.isEmpty ? "" : " " + format), hash: text(torrent["hash"]),
                        size: number(torrent["size_bytes"]), seeders: number(torrent["seeds"]), peers: number(torrent["peers"]),
                        date: epochDate(torrent["date_uploaded_unix"]), categories: ["2000"], details: webURL(movie["url"]),
                        poster: webURL(movie["medium_cover_image"]), summary: text(movie["summary"]), year: text(movie["year"]))
                }
            }
        default: throw invalidResponse
        }
    }

    private static func parseHTML(_ data: Data, provider: TorrentSearchProvider, pageURL: URL) throws -> [JackettSearchResult] {
        // Native libxml HTML recovery handles optional closing tags and entities.
        // External entities are never loaded from a third-party search response.
        let options: XMLNode.Options = [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
        // The data initializer guesses Latin-1 for HTML5's short charset tag.
        // Decode valid UTF-8 explicitly so Cyrillic titles and dates survive.
        let document: XMLDocument
        if let html = String(data: data, encoding: .utf8) {
            document = try XMLDocument(xmlString: html, options: options)
        } else {
            document = try XMLDocument(data: data, options: options)
        }
        let container: String = provider == .rutor ? "//div[@id='index']//table" : "//table[contains(concat(' ', normalize-space(@class), ' '), ' torrent-list ')]"
        let tables = try document.nodes(forXPath: container)
        guard !tables.isEmpty else {
            let pageText = (document.rootElement()?.stringValue ?? "").lowercased()
            if pageText.contains("no results found") || pageText.contains("ничего не найдено") { return [] }
            throw invalidResponse
        }
        let rows = try document.nodes(forXPath: container + "//tr[td]")
        return try rows.compactMap { row in
            let cells = try row.nodes(forXPath: "./td")
            if provider == .rutor {
                guard cells.count >= 4,
                      let title = try row.nodes(forXPath: "./td[2]/a[contains(@href, '/torrent/')]").last,
                      let magnet = webURL(try attribute(row, xpath: ".//a[starts-with(@href, 'magnet:')]", name: "href"), allowMagnet: true) else { return nil }
                return makeResult(provider: provider, title: title.stringValue ?? "", hash: "", magnet: magnet,
                    size: fileSize(cells[cells.count - 2].stringValue ?? ""),
                    seeders: number(try value(row, xpath: "./td[last()]/span[1]")),
                    peers: number(try value(row, xpath: "./td[last()]/span[3]")),
                    date: russianDate(cells[0].stringValue ?? ""),
                    details: webURL((title as? XMLElement)?.attribute(forName: "href")?.stringValue, relativeTo: pageURL))
            }
            guard cells.count >= 7,
                  let title = try row.nodes(forXPath: "./td[2]/a[not(contains(@class, 'comments'))]").last,
                  let magnet = webURL(try attribute(row, xpath: ".//a[starts-with(@href, 'magnet:')]", name: "href"), allowMagnet: true) else { return nil }
            return makeResult(provider: provider, title: title.stringValue ?? "", hash: "", magnet: magnet,
                size: fileSize(cells[3].stringValue ?? ""), seeders: number(cells[5].stringValue), peers: number(cells[6].stringValue),
                date: epochDate((cells[4] as? XMLElement)?.attribute(forName: "data-timestamp")?.stringValue),
                categories: ["5000"], details: webURL((title as? XMLElement)?.attribute(forName: "href")?.stringValue, relativeTo: pageURL))
        }
    }

    private static func makeResult(
        provider: TorrentSearchProvider, title: String, hash: String, magnet: URL? = nil,
        size: Int64 = 0, seeders: Int64 = 0, peers: Int64 = 0, date: Date? = nil,
        categories: [String] = [], details: URL? = nil, poster: URL? = nil, summary: String = "", year: String = ""
    ) -> JackettSearchResult? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let hash = TorrentSearchIdentity.hash(in: magnet) ?? TorrentSearchIdentity.normalizedHash(hash),
              let magnet = magnet ?? TorrentSearchIdentity.magnet(hash: hash, title: title) else { return nil }
        return JackettSearchResult(id: "btih:\(hash)", title: String(title.prefix(2000)), summary: String(summary.prefix(20_000)), tracker: provider.title,
            downloadURL: nil, magnetURL: magnet, posterURL: poster, detailsURL: details, size: max(size, 0),
            seeders: Int(clamping: max(seeders, 0)), peers: Int(clamping: max(peers, 0)), categories: categories,
            publishedAt: date, infoHash: hash, year: year)
    }

    private static var invalidResponse: AppError { AppError("The source returned an unexpected response or a verification page. Try another source.") }
    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    private static func number(_ value: Any?) -> Int64 {
        let string = text(value).replacingOccurrences(of: ",", with: "").filter { !$0.isWhitespace }
        return max(Int64(string) ?? 0, 0)
    }
    static func fileSize(_ value: String) -> Int64 {
        let value = value.replacingOccurrences(of: ",", with: ".").uppercased()
        guard let expression = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?I?B|[КМГТ]?Б)"#),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let numberRange = Range(match.range(at: 1), in: value), let unitRange = Range(match.range(at: 2), in: value),
              let amount = Double(value[numberRange]) else { return 0 }
        let unit = String(value[unitRange])
        let power: Int
        switch unit.first {
        case "K", "К": power = 1
        case "M", "М": power = 2
        case "G", "Г": power = 3
        case "T", "Т": power = 4
        default: power = 0
        }
        let bytes = amount * pow(1024, Double(power))
        guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return 0 }
        return Int64(bytes)
    }
    private static func webURL(_ value: Any?, relativeTo base: URL? = nil, allowMagnet: Bool = false) -> URL? {
        let string = text(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty, let url = URL(string: string, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased() else { return nil }
        if allowMagnet { return scheme == "magnet" && TorrentSearchIdentity.hash(in: url) != nil ? url : nil }
        return ["https", "http"].contains(scheme) && url.host != nil ? url : nil
    }
    private static func epochDate(_ value: Any?) -> Date? {
        let number = number(value)
        guard number > 0, number < 32_503_680_000 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(number))
    }
    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
    private static func russianDate(_ value: String) -> Date? {
        var value = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (ru, en) in ["янв": "Jan", "фев": "Feb", "мар": "Mar", "апр": "Apr", "май": "May", "июн": "Jun", "июл": "Jul", "авг": "Aug", "сен": "Sep", "окт": "Oct", "ноя": "Nov", "дек": "Dec"] {
            value = value.replacingOccurrences(of: ru, with: en)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yy"
        return formatter.date(from: value)
    }
    private static func value(_ node: XMLNode, xpath: String) throws -> String {
        try node.nodes(forXPath: xpath).first?.stringValue ?? ""
    }
    private static func attribute(_ node: XMLNode, xpath: String, name: String) throws -> String {
        try (node.nodes(forXPath: xpath).first as? XMLElement)?.attribute(forName: name)?.stringValue ?? ""
    }
}

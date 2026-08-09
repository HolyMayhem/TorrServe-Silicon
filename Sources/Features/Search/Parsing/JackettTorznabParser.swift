import Foundation

final class JackettTorznabParser: NSObject, XMLParserDelegate {
    private struct Draft {
        var title = ""
        var guid = ""
        var summary = ""
        var tracker = ""
        var link = ""
        var enclosure = ""
        var magnet = ""
        var poster = ""
        var details = ""
        var size: Int64 = 0
        var seeders = 0
        var peers = 0
        var categories: [String] = []
        var publishedAt: Date?
        var infoHash = ""
        var year = ""
    }

    private let data: Data
    private var results: [JackettSearchResult] = []
    private var draft: Draft?
    private var elementName = ""
    private var characters = ""
    private var parserError: Error?

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [JackettSearchResult] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parserError
                ?? parser.parserError
                ?? AppError("Jackett returned invalid XML.")
        }
        return results
    }

    static func errorMessage(in data: Data) -> String? {
        guard
            let value = String(data: data, encoding: .utf8),
            let range = value.range(
                of: #"description="([^"]+)""#,
                options: .regularExpression
            )
        else {
            return nil
        }
        let match = String(value[range])
        return match
            .replacingOccurrences(of: #"description=""#, with: "")
            .dropLast()
            .description
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        self.elementName = elementName
        characters = ""

        if elementName == "item" {
            draft = Draft()
            return
        }
        guard draft != nil else { return }

        if elementName == "enclosure" {
            draft?.enclosure = attributeDict["url"] ?? ""
            if let length = attributeDict["length"] {
                draft?.size = Int64(length) ?? draft?.size ?? 0
            }
        } else if elementName == "attr" || elementName.hasSuffix(":attr") {
            applyAttribute(
                name: attributeDict["name"] ?? "",
                value: attributeDict["value"] ?? ""
            )
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        characters += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var value = draft else { return }
        let text = characters.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title": value.title = text
        case "guid": value.guid = text
        case "description": value.summary = Self.plainText(text)
        case "jackettindexer": value.tracker = text
        case "link": value.link = text
        case "comments": value.details = text
        case "size": value.size = Int64(text) ?? value.size
        case "category":
            if !text.isEmpty {
                value.categories.append(text)
            }
        case "pubDate": value.publishedAt = Self.parseDate(text)
        case "item":
            results.append(Self.result(from: value))
            draft = nil
            characters = ""
            return
        default:
            break
        }

        draft = value
        characters = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }

    private func applyAttribute(name: String, value: String) {
        switch name.lowercased() {
        case "seeders": draft?.seeders = Int(value) ?? 0
        case "peers": draft?.peers = Int(value) ?? 0
        case "coverurl": draft?.poster = value
        case "magneturl": draft?.magnet = value
        case "infohash": draft?.infoHash = value
        case "year": draft?.year = value
        case "category":
            if !value.isEmpty {
                draft?.categories.append(value)
            }
        default:
            break
        }
    }

    private static func result(from value: Draft) -> JackettSearchResult {
        let linkURL = URL(string: value.enclosure.isEmpty ? value.link : value.enclosure)
        let directMagnet = URL(string: value.magnet)
        let downloadURL: URL?
        let magnetURL: URL?

        if linkURL?.scheme?.lowercased() == "magnet" {
            downloadURL = nil
            magnetURL = directMagnet ?? linkURL
        } else {
            downloadURL = linkURL
            magnetURL = directMagnet
        }

        return JackettSearchResult(
            id: value.guid.isEmpty
                ? (value.infoHash.isEmpty ? value.link : value.infoHash)
                : value.guid,
            title: value.title.isEmpty ? "Torrent" : value.title,
            summary: value.summary,
            tracker: value.tracker,
            downloadURL: downloadURL,
            magnetURL: magnetURL,
            posterURL: URL(string: value.poster),
            detailsURL: URL(string: value.details),
            size: value.size,
            seeders: value.seeders,
            peers: value.peers,
            categories: Array(Set(value.categories)),
            publishedAt: value.publishedAt,
            infoHash: value.infoHash,
            year: value.year
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: value)
    }

    private static func plainText(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

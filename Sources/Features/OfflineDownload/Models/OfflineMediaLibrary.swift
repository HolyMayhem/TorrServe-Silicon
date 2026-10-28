import Foundation

struct OfflineMediaGroup: Identifiable {
    let id: String
    let title: String
    let posterURL: String?
    let isSeries: Bool
    let records: [OfflineDownloadRecord]

    var totalBytes: Int64 { records.reduce(0) { $0 + $1.expectedLength } }
    var latestDownload: Date { records.map(\.completedAt).max() ?? .distantPast }

    var fileSections: [OfflineMediaFileSection] {
        guard isSeries else { return [.init(season: nil, records: records)] }
        return Dictionary(grouping: records) { OfflineMediaLibrary.season(in: $0.destinationURL.lastPathComponent) }
            .map { OfflineMediaFileSection(season: $0.key, records: $0.value) }
            .sorted { ($0.season ?? Int.max) < ($1.season ?? Int.max) }
    }
}

struct OfflineMediaFileSection: Identifiable {
    let season: Int?
    let records: [OfflineDownloadRecord]
    var id: Int { season ?? -1 }
}

enum OfflineMediaLibrary {
    private static let episodeExpression = try? NSRegularExpression(pattern: #"(?i)(?:\bS(\d{1,2})[ ._-]*E(\d{1,3})\b|\b(\d{1,2})x(\d{1,3})\b)"#)
    static func torrentHash(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "link" && $0.value?.isEmpty == false }?.value?.lowercased()
    }

    static func groups(
        records: [OfflineDownloadRecord],
        catalog: [String: OfflineMediaInfo] = [:]
    ) -> [OfflineMediaGroup] {
        // A newer saved episode can also identify older records from its torrent.
        var known = [String: OfflineMediaInfo]()
        for record in records.sorted(by: { $0.completedAt < $1.completedAt }) {
            if let media = record.media, let hash = media.torrentHash {
                known[hash.lowercased()] = media
            }
        }
        let seriesHashes = Set(records.compactMap { record -> String? in
            guard record.media?.isSeries == true || season(in: record.destinationURL.lastPathComponent) != nil else { return nil }
            return torrentHash(in: record.sourceURL) ?? record.media?.torrentHash?.lowercased()
        })
        for (hash, media) in catalog {
            let key = hash.lowercased()
            // A movie metadata mismatch must not override known episode files.
            if seriesHashes.contains(key), !media.isSeries { continue }
            known[key] = OfflineMediaInfo(id: media.id, title: media.title, posterURL: media.posterURL ?? known[key]?.posterURL, isSeries: media.isSeries, torrentHash: media.torrentHash)
        }
        var grouped = [String: (OfflineMediaInfo, [OfflineDownloadRecord])]()
        for record in records {
            let hash = torrentHash(in: record.sourceURL) ?? record.media?.torrentHash?.lowercased()
            let media = hash.flatMap { known[$0] } ?? record.media ?? fallback(for: record, hash: hash)
            if grouped[media.id] == nil { grouped[media.id] = (media, []) }
            grouped[media.id]?.1.append(record)
        }
        return grouped.map { id, value in
            let files = value.1.sorted {
                let left = episode(in: $0.destinationURL.lastPathComponent)
                let right = episode(in: $1.destinationURL.lastPathComponent)
                switch (left, right) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
                return $0.destinationURL.lastPathComponent.localizedStandardCompare($1.destinationURL.lastPathComponent) == .orderedAscending
            }
            return OfflineMediaGroup(
                id: id, title: value.0.title, posterURL: value.0.posterURL,
                isSeries: value.0.isSeries || files.contains { season(in: $0.destinationURL.lastPathComponent) != nil },
                records: files
            )
        }.sorted {
            if $0.latestDownload != $1.latestDownload { return $0.latestDownload > $1.latestDownload }
            return $0.id < $1.id
        }
    }

    static func season(in filename: String) -> Int? {
        episode(in: filename)?.season
    }

    static func episode(in filename: String) -> (season: Int, episode: Int)? {
        guard let regex = episodeExpression,
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)) else { return nil }
        for index in [1, 3] {
            if let seasonRange = Range(match.range(at: index), in: filename),
               let episodeRange = Range(match.range(at: index + 1), in: filename),
               let season = Int(filename[seasonRange]), let episode = Int(filename[episodeRange]) { return (season, episode) }
        }
        return nil
    }

    private static func fallback(for record: OfflineDownloadRecord, hash: String?) -> OfflineMediaInfo {
        let filename = record.sourceURL.lastPathComponent.isEmpty
            ? record.destinationURL.lastPathComponent : record.sourceURL.lastPathComponent
        let name = (filename as NSString).deletingPathExtension
        let isSeries = season(in: filename) != nil
        let title = isSeries
            ? name.replacingOccurrences(of: #"(?i)[ ._-]*(?:S\d{1,2}[ ._-]*E\d{1,3}|\d{1,2}x\d{1,3}).*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ".", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            : name
        return OfflineMediaInfo(
            id: hash.map { "torrent:\($0)" } ?? "source:\(record.sourceURL.absoluteString)",
            title: title.isEmpty ? name : title, posterURL: nil, isSeries: isSeries, torrentHash: hash
        )
    }
}

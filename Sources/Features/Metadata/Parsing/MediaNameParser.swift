import Foundation

protocol MediaNameParsing: Sendable {
    func parse(_ value: String) -> ParsedMediaName
}

struct MediaNameParser: MediaNameParsing {
    private static let episodePatterns = [
        #"(?i)\bS(\d{1,2})[\s._-]*E(\d{1,3})\b"#,
        #"(?i)\b(\d{1,2})x(\d{1,3})\b"#
    ]
    private static let seasonPattern = #"(?i)\b(?:S|Season[\s._-]*)(\d{1,2})\b"#
    private static let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
    private static let technicalPattern = #"(?i)\b(?:2160p|1440p|1080p|720p|576p|480p|4K|UHD|HDR10\+?|HDR|DV|DoVi|REMUX|BluRay|BDRip|BRRip|WEB[ ._-]?(?:DL|Rip)|HDTV|DVDRip|x26[45]|h26[45]|HEVC|AVC|AV1|AAC|AC3|EAC3|DTS(?:-HD)?|Atmos|TrueHD|FLAC|MULTI|DUAL|PROPER|REPACK|EXTENDED|UNRATED|COMPLETE)\b"#

    func parse(_ value: String) -> ParsedMediaName {
        let filename = mediaName(from: value)
        let normalized = normalize(filename)
        let episodeMatch = firstEpisodeMatch(in: normalized)
        let season = episodeMatch?.season ?? firstInteger(
            matching: Self.seasonPattern,
            group: 1,
            in: normalized
        )
        let episode = episodeMatch?.episode
        let year = lastInteger(matching: Self.yearPattern, group: 1, in: normalized)

        let cutLocations = [
            lastRange(matching: Self.yearPattern, in: normalized)?.lowerBound,
            episodeMatch?.range.lowerBound,
            firstRange(matching: Self.seasonPattern, in: normalized)?.lowerBound,
            firstRange(matching: Self.technicalPattern, in: normalized)?.lowerBound
        ].compactMap { $0 }

        let titleEnd = cutLocations.min() ?? normalized.endIndex
        var title = String(normalized[..<titleEnd])
        title = cleanupTitle(title)

        if title.isEmpty {
            title = cleanupTitle(normalized)
        }

        return ParsedMediaName(
            title: title.isEmpty ? "Unknown" : title,
            year: year,
            kind: season != nil || episode != nil ? .tv : .movie,
            season: season,
            episode: episode
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[._+]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\]{}()]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)\b(?:the)?piratebay\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "-–—")
            ))
    }

    private func mediaName(from value: String) -> String {
        let path = value as NSString
        let mediaExtensions: Set<String> = [
            "mkv", "mp4", "m4v", "avi", "mov", "wmv", "webm", "ts", "m2ts", "torrent"
        ]
        guard mediaExtensions.contains(path.pathExtension.lowercased()) else {
            return value
        }
        return (path.lastPathComponent as NSString).deletingPathExtension
    }

    private func firstEpisodeMatch(
        in value: String
    ) -> (season: Int, episode: Int, range: Range<String.Index>)? {
        for pattern in Self.episodePatterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..<value.endIndex, in: value)
                ),
                let fullRange = Range(match.range(at: 0), in: value),
                let seasonRange = Range(match.range(at: 1), in: value),
                let episodeRange = Range(match.range(at: 2), in: value),
                let season = Int(value[seasonRange]),
                let episode = Int(value[episodeRange])
            else {
                continue
            }
            return (season, episode, fullRange)
        }
        return nil
    }

    private func firstInteger(
        matching pattern: String,
        group: Int,
        in value: String
    ) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            ),
            match.numberOfRanges > group,
            let range = Range(match.range(at: group), in: value)
        else {
            return nil
        }
        return Int(value[range])
    }

    private func lastInteger(
        matching pattern: String,
        group: Int,
        in value: String
    ) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.matches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            ).last,
            match.numberOfRanges > group,
            let range = Range(match.range(at: group), in: value)
        else {
            return nil
        }
        return Int(value[range])
    }

    private func firstRange(
        matching pattern: String,
        in value: String
    ) -> Range<String.Index>? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            )
        else {
            return nil
        }
        return Range(match.range(at: 0), in: value)
    }

    private func lastRange(
        matching pattern: String,
        in value: String
    ) -> Range<String.Index>? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.matches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            ).last
        else {
            return nil
        }
        return Range(match.range(at: 0), in: value)
    }
}

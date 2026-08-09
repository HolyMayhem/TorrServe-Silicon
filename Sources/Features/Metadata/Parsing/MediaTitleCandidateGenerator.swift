import Foundation

protocol MediaTitleCandidateGenerating: Sendable {
    func candidates(
        from sourceValues: [String],
        provider: MetadataProvider,
        language: String
    ) -> [MediaTitleCandidate]
}

struct MediaTitleCandidateGenerator: MediaTitleCandidateGenerating {
    private let parser: MediaNameParsing
    private let maximumCandidates = 5

    init(parser: MediaNameParsing = MediaNameParser()) {
        self.parser = parser
    }

    func candidates(
        from sourceValues: [String],
        provider: MetadataProvider,
        language: String
    ) -> [MediaTitleCandidate] {
        var values: [String: MediaTitleCandidate] = [:]

        for (sourceIndex, source) in sourceValues.enumerated() where !source.isEmpty {
            let sourceConfidence = max(35, 100 - sourceIndex * 20)
            for variant in variants(from: source) {
                let parsed = parser.parse(variant.value)
                guard parsed.title != "Unknown", !parsed.title.isEmpty else { continue }

                let confidence = sourceConfidence
                    + variant.bonus
                    + scriptBonus(parsed.title, provider: provider, language: language)
                    - noisePenalty(parsed.title)
                let key = Self.normalizedKey(parsed)
                let candidate = MediaTitleCandidate(
                    parsedName: parsed,
                    confidence: confidence
                )
                if confidence > (values[key]?.confidence ?? .min) {
                    values[key] = candidate
                }
            }
        }

        return values.values
            .sorted { left, right in
                if left.confidence != right.confidence {
                    return left.confidence > right.confidence
                }
                return left.parsedName.title.count < right.parsedName.title.count
            }
            .prefix(maximumCandidates)
            .map { $0 }
    }

    private func variants(from source: String) -> [(value: String, bonus: Int)] {
        let year = releaseYear(in: source)
        let suffix = year.map { " \($0)" } ?? ""
        let prefix = titlePrefix(from: source)
        let withoutParentheses = replacingParentheticalText(in: prefix, with: " ")

        var values: [(String, Int)] = [
            (prefix + suffix, 0),
            (withoutParentheses + suffix, 24)
        ]

        for part in splitAliases(withoutParentheses) {
            values.append((part + suffix, 60))
        }

        // In tracker titles, text after an already bilingual "Title / Original"
        // pair usually names the director, voice-over, or edition rather than the movie.
        // Parenthetical aliases remain useful for the common "Title (Original Title)" form.
        if !containsAliasSeparator(withoutParentheses) {
            for parenthetical in parentheticalValues(in: prefix) {
                for part in splitAliases(parenthetical) {
                    values.append((part + suffix, 8))
                }
            }
        }

        return values.filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func titlePrefix(from source: String) -> String {
        let filename = mediaName(from: source)
        let yearRanges = matches(pattern: #"\b(?:19|20)\d{2}\b"#, in: filename)
        let technicalRange = firstMatch(
            pattern: #"(?i)\b(?:2160p|1440p|1080p|720p|576p|480p|4K|UHD|HDR|REMUX|BluRay|BDRip|BRRip|WEB[ ._-]?(?:DL|Rip)|HDTV|DVDRip|x26[45]|h26[45]|HEVC|AVC|AV1)\b"#,
            in: filename
        )

        let releaseYearRange = yearRanges.last
        let cutLocation = [releaseYearRange?.lowerBound, technicalRange?.lowerBound]
            .compactMap { $0 }
            .min() ?? filename.endIndex
        return String(filename[..<cutLocation])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "[]{}_-–—")
            ))
    }

    private func releaseYear(in source: String) -> Int? {
        let filename = mediaName(from: source)
        guard let range = matches(
            pattern: #"\b(?:19|20)\d{2}\b"#,
            in: filename
        ).last else {
            return nil
        }
        return Int(filename[range])
    }

    private func splitAliases(_ value: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*(?:/|\||\baka\b)\s*"#,
            options: [.caseInsensitive]
        ) else {
            return [value]
        }
        return value
            .components(separatedBy: regex)
            .map {
                $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "[]{}()_-–—")
                ))
            }
            .filter { !$0.isEmpty }
    }

    private func containsAliasSeparator(_ value: String) -> Bool {
        value.contains("/")
            || value.contains("|")
            || value.range(of: #"(?i)\baka\b"#, options: .regularExpression) != nil
    }

    private func replacingParentheticalText(in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\([^)]*\)"#) else {
            return value
        }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }

    private func parentheticalValues(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\(([^)]*)\)"#) else {
            return []
        }
        return regex.matches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value) else {
                return nil
            }
            return String(value[range])
        }
    }

    private func scriptBonus(
        _ title: String,
        provider: MetadataProvider,
        language: String
    ) -> Int {
        let hasLatin = title.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let hasCyrillic = title.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil

        switch provider {
        case .omdb:
            if hasLatin && !hasCyrillic { return 32 }
            if hasCyrillic && !hasLatin { return -12 }
        case .tmdb:
            if language.hasPrefix("ru"), hasCyrillic && !hasLatin { return 24 }
            if hasLatin && !hasCyrillic { return 16 }
        }
        return 0
    }

    private func noisePenalty(_ title: String) -> Int {
        let wordCount = title.split(separator: " ").count
        let excessWords = max(0, wordCount - 6)
        let separatorPenalty = title.contains("/") || title.contains("|") ? 18 : 0
        return excessWords * 4 + separatorPenalty
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

    private func firstMatch(pattern: String, in value: String) -> Range<String.Index>? {
        matches(pattern: pattern, in: value).first
    }

    private func matches(pattern: String, in value: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ).compactMap { Range($0.range, in: value) }
    }

    private static func normalizedKey(_ parsed: ParsedMediaName) -> String {
        [
            parsed.title.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            ).lowercased(),
            parsed.year.map(String.init) ?? "-",
            parsed.kind.rawValue
        ].joined(separator: "|")
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var values: [String] = []
        var previousLocation = range.location

        for match in regex.matches(in: self, range: range) {
            let partRange = NSRange(
                location: previousLocation,
                length: match.range.location - previousLocation
            )
            if let swiftRange = Range(partRange, in: self) {
                values.append(String(self[swiftRange]))
            }
            previousLocation = match.range.location + match.range.length
        }

        let tailRange = NSRange(
            location: previousLocation,
            length: range.location + range.length - previousLocation
        )
        if let swiftRange = Range(tailRange, in: self) {
            values.append(String(self[swiftRange]))
        }
        return values
    }
}

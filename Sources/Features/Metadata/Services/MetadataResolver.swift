import Foundation

actor MetadataResolver {
    private let candidateGenerator: MediaTitleCandidateGenerating
    private let services: [MetadataProvider: any MetadataServicing]
    private let cache: MetadataCache

    init(
        candidateGenerator: MediaTitleCandidateGenerating = MediaTitleCandidateGenerator(),
        services: [any MetadataServicing] = [TMDBService(), OMDBService()],
        cache: MetadataCache = .shared
    ) {
        self.candidateGenerator = candidateGenerator
        self.services = Dictionary(uniqueKeysWithValues: services.map { ($0.provider, $0) })
        self.cache = cache
    }

    func resolve(
        candidates: [String],
        provider: MetadataProvider,
        language: String,
        forceRefresh: Bool = false
    ) async -> MetadataResolutionOutcome {
        let titleCandidates = candidateGenerator.candidates(
            from: candidates,
            provider: provider,
            language: language
        )
        guard let primaryCandidate = titleCandidates.first else {
            return .notFound
        }
        guard let service = services[provider] else { return .unavailable }
        let cacheKey = Self.cacheKey(
            candidates: titleCandidates,
            provider: provider,
            language: language
        )
        if forceRefresh {
            await cache.removeValue(for: cacheKey)
        } else {
            switch await cache.value(for: cacheKey) {
            case .missing:
                break
            case .cached(let metadata):
                guard let metadata else { return .notFound }
                return .resolved(ResolvedMediaMetadata(
                    parsedName: primaryCandidate.parsedName,
                    metadata: metadata
                ))
            }
        }

        do {
            let queryCandidates = Self.queryCandidates(from: titleCandidates)
            var selectedMatch: CandidateMatch?

            for query in queryCandidates {
                let parsed = query.candidate.parsedName
                let results = try await service.search(
                    title: parsed.title,
                    year: parsed.year,
                    kind: query.kind,
                    language: language
                )
                guard let result = Self.bestResult(in: results, for: parsed) else {
                    continue
                }

                let resultRanking = Self.ranking(for: result, parsed: parsed)
                let match = CandidateMatch(
                    result: result,
                    parsedName: parsed,
                    ranking: CandidateResolutionRanking(
                        title: resultRanking.title,
                        year: resultRanking.year,
                        kind: resultRanking.kind,
                        confidence: query.candidate.confidence,
                        popularity: resultRanking.popularity
                    )
                )
                if selectedMatch == nil || selectedMatch!.ranking < match.ranking {
                    selectedMatch = match
                }

                let yearMatches = parsed.year == nil || result.releaseYear == parsed.year
                if resultRanking.title == 3,
                   yearMatches,
                   result.kind == parsed.kind {
                    break
                }
            }

            guard let selectedMatch else {
                await cache.save(nil, for: cacheKey)
                return .notFound
            }
            let details = try await service.details(
                id: selectedMatch.result.id,
                kind: selectedMatch.result.kind,
                language: language
            )
            await cache.save(details, for: cacheKey)
            return .resolved(ResolvedMediaMetadata(
                parsedName: selectedMatch.parsedName,
                metadata: details
            ))
        } catch {
            return .unavailable
        }
    }

    static func bestResult(
        in results: [MediaSearchResult],
        for parsed: ParsedMediaName
    ) -> MediaSearchResult? {
        results.max { left, right in
            ranking(for: left, parsed: parsed) < ranking(for: right, parsed: parsed)
        }
    }

    private static func ranking(
        for result: MediaSearchResult,
        parsed: ParsedMediaName
    ) -> ResultRanking {
        let localizedMatch = titleMatch(result.localizedTitle, parsed.title)
        let originalMatch = titleMatch(result.originalTitle, parsed.title)
        return ResultRanking(
            title: max(localizedMatch, originalMatch),
            year: parsed.year == nil ? 0 : (result.releaseYear == parsed.year ? 1 : 0),
            kind: result.kind == parsed.kind ? 1 : 0,
            popularity: result.popularity
        )
    }

    private static func titleMatch(_ candidate: String, _ requested: String) -> Double {
        let left = normalizedTitle(candidate)
        let right = normalizedTitle(requested)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 3 }
        if left.contains(right) || right.contains(left) { return 2 }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let union = leftTokens.union(rightTokens)
        guard !union.isEmpty else { return 0 }
        return Double(leftTokens.intersection(rightTokens).count) / Double(union.count)
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cacheKey(
        candidates: [MediaTitleCandidate],
        provider: MetadataProvider,
        language: String
    ) -> String {
        let candidateKey = candidates.map { candidate in
            let parsed = candidate.parsedName
            return [
                normalizedTitle(parsed.title),
                parsed.year.map(String.init) ?? "-",
                parsed.kind.rawValue
            ].joined(separator: ":")
        }.joined(separator: "|")
        return [
            "v2",
            provider.rawValue,
            language,
            candidateKey
        ].joined(separator: "|")
    }

    private static func queryCandidates(
        from candidates: [MediaTitleCandidate]
    ) -> [(candidate: MediaTitleCandidate, kind: MediaKind)] {
        let primary = candidates.prefix(4).map { ($0, $0.parsedName.kind) }
        let fallback = candidates.prefix(2).map { candidate in
            let kind: MediaKind = candidate.parsedName.kind == .movie ? .tv : .movie
            return (candidate, kind)
        }
        return primary + fallback
    }
}

private struct ResultRanking: Comparable {
    let title: Double
    let year: Int
    let kind: Int
    let popularity: Double

    static func < (left: ResultRanking, right: ResultRanking) -> Bool {
        if left.title != right.title { return left.title < right.title }
        if left.year != right.year { return left.year < right.year }
        if left.kind != right.kind { return left.kind < right.kind }
        return left.popularity < right.popularity
    }
}

private struct CandidateMatch {
    let result: MediaSearchResult
    let parsedName: ParsedMediaName
    let ranking: CandidateResolutionRanking
}

private struct CandidateResolutionRanking: Comparable {
    let title: Double
    let year: Int
    let kind: Int
    let confidence: Int
    let popularity: Double

    static func < (
        left: CandidateResolutionRanking,
        right: CandidateResolutionRanking
    ) -> Bool {
        if left.title != right.title { return left.title < right.title }
        if left.year != right.year { return left.year < right.year }
        if left.kind != right.kind { return left.kind < right.kind }
        if left.confidence != right.confidence { return left.confidence < right.confidence }
        return left.popularity < right.popularity
    }
}

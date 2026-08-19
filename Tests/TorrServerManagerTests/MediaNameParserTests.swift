import XCTest
@testable import TorrServerManager

final class MediaNameParserTests: XCTestCase {
    private let parser = MediaNameParser()

    func testParsesMovieNameAndYear() {
        let value = parser.parse("Dune.Part.Two.2024.2160p.REMUX.DV.mkv")

        XCTAssertEqual(value.title, "Dune Part Two")
        XCTAssertEqual(value.year, 2024)
        XCTAssertEqual(value.kind, .movie)
        XCTAssertNil(value.season)
        XCTAssertNil(value.episode)
    }

    func testParsesTVSeasonAndEpisode() {
        let value = parser.parse("The.Last.of.Us.S02E03.2160p.WEB-DL")

        XCTAssertEqual(value.title, "The Last of Us")
        XCTAssertNil(value.year)
        XCTAssertEqual(value.kind, .tv)
        XCTAssertEqual(value.season, 2)
        XCTAssertEqual(value.episode, 3)
    }

    func testParsesAlternativeEpisodeNotation() {
        let value = parser.parse("Severance.1x08.1080p.WEBRip.mkv")

        XCTAssertEqual(value.title, "Severance")
        XCTAssertEqual(value.kind, .tv)
        XCTAssertEqual(value.season, 1)
        XCTAssertEqual(value.episode, 8)
    }

    func testStopsAtTechnicalTokensWithoutYear() {
        let value = parser.parse("Blade.Runner.Final.Cut.1080p.BluRay.x265.mkv")

        XCTAssertEqual(value.title, "Blade Runner Final Cut")
        XCTAssertEqual(value.kind, .movie)
    }

    func testUsesLastYearWhenTitleContainsAProductionYear() {
        let value = parser.parse("Blade.Runner.2049.2017.2160p.mkv")

        XCTAssertEqual(value.title, "Blade Runner 2049")
        XCTAssertEqual(value.year, 2017)
    }
}

final class MediaTitleCandidateGeneratorTests: XCTestCase {
    private let releaseName = """
    Кровавый четверг / Thursday (Скип Вудс / Skip Woods) [1998, США, боевик, триллер, драма, криминал, BDRip-AVC] AVO + MVO + Sub + Original eng
    """

    func testPrioritizesLatinAliasForOMDB() {
        let values = MediaTitleCandidateGenerator().candidates(
            from: [releaseName],
            provider: .omdb,
            language: "en-US"
        )

        XCTAssertEqual(values.first?.parsedName.title, "Thursday")
        XCTAssertEqual(values.first?.parsedName.year, 1998)
    }

    func testPrioritizesLocalizedAliasForRussianTMDB() {
        let values = MediaTitleCandidateGenerator().candidates(
            from: [releaseName],
            provider: .tmdb,
            language: "ru-RU"
        )

        XCTAssertEqual(values.first?.parsedName.title, "Кровавый четверг")
        XCTAssertEqual(values.first?.parsedName.year, 1998)
    }

    func testResolverFallsBackToCleanAlias() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = MetadataResolver(
            services: [ThursdayMetadataService()],
            cache: MetadataCache(fileURL: directory.appendingPathComponent("cache.json"))
        )

        let outcome = await resolver.resolve(
            candidates: [releaseName],
            provider: .omdb,
            language: "en-US"
        )

        guard case .resolved(let value) = outcome else {
            return XCTFail("Expected Thursday metadata to resolve")
        }
        XCTAssertEqual(value.parsedName.title, "Thursday")
        XCTAssertEqual(value.metadata.localizedTitle, "Thursday")
    }
}

private struct ThursdayMetadataService: MetadataServicing {
    let provider = MetadataProvider.omdb

    func search(
        title: String,
        year: Int?,
        kind: MediaKind,
        language: String
    ) async throws -> [MediaSearchResult] {
        guard title == "Thursday", year == 1998, kind == .movie else { return [] }
        return [MediaSearchResult(
            id: "tt0124901",
            provider: .omdb,
            kind: .movie,
            localizedTitle: "Thursday",
            originalTitle: "Thursday",
            releaseDate: "1998",
            posterURL: nil,
            backdropURL: nil,
            overview: "",
            rating: 7.1,
            popularity: 0
        )]
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        MediaMetadata(
            id: id,
            provider: .omdb,
            kind: kind,
            localizedTitle: "Thursday",
            originalTitle: "Thursday",
            overview: "",
            genres: ["Action"],
            runtimeMinutes: 87,
            releaseDate: "1998",
            rating: 7.1,
            posterURL: nil,
            backdropURL: nil
        )
    }
}

final class MetadataResolverRankingTests: XCTestCase {
    func testExactTitleWinsBeforePopularity() {
        let parsed = ParsedMediaName(
            title: "Dune Part Two",
            year: 2024,
            kind: .movie,
            season: nil,
            episode: nil
        )
        let exact = result(
            id: 1,
            title: "Dune: Part Two",
            year: 2024,
            kind: .movie,
            popularity: 10
        )
        let popularPartial = result(
            id: 2,
            title: "Dune",
            year: 2024,
            kind: .movie,
            popularity: 1_000
        )

        XCTAssertEqual(
            MetadataResolver.bestResult(in: [popularPartial, exact], for: parsed)?.id,
            exact.id
        )
    }

    func testYearWinsBeforeTypeAndPopularityWhenTitlesMatch() {
        let parsed = ParsedMediaName(
            title: "The Last of Us",
            year: 2023,
            kind: .tv,
            season: 1,
            episode: 1
        )
        let wrongYear = result(
            id: 1,
            title: "The Last of Us",
            year: 2014,
            kind: .tv,
            popularity: 1_000
        )
        let rightYear = result(
            id: 2,
            title: "The Last of Us",
            year: 2023,
            kind: .tv,
            popularity: 10
        )

        XCTAssertEqual(
            MetadataResolver.bestResult(in: [wrongYear, rightYear], for: parsed)?.id,
            rightYear.id
        )
    }

    func testPopularityBreaksAnOtherwiseEqualTie() {
        let parsed = ParsedMediaName(
            title: "Foundation",
            year: nil,
            kind: .tv,
            season: 2,
            episode: 3
        )
        let low = result(
            id: 1,
            title: "Foundation",
            year: 2021,
            kind: .tv,
            popularity: 5
        )
        let high = result(
            id: 2,
            title: "Foundation",
            year: 2021,
            kind: .tv,
            popularity: 50
        )

        XCTAssertEqual(
            MetadataResolver.bestResult(in: [low, high], for: parsed)?.id,
            high.id
        )
    }

    private func result(
        id: Int,
        title: String,
        year: Int,
        kind: MediaKind,
        popularity: Double
    ) -> MediaSearchResult {
        MediaSearchResult(
            id: String(id),
            provider: .tmdb,
            kind: kind,
            localizedTitle: title,
            originalTitle: title,
            releaseDate: "\(year)-01-01",
            posterURL: nil,
            backdropURL: nil,
            overview: "",
            rating: 0,
            popularity: popularity
        )
    }
}

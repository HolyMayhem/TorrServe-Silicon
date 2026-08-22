import Foundation
import XCTest
@testable import TorrServerManager

final class AniListServiceTests: XCTestCase {
    override func tearDown() {
        AniListURLProtocol.responseData = nil
        AniListURLProtocol.capturedRequests = []
        AniListURLProtocol.capturedBodies = []
        super.tearDown()
    }

    func testSearchPostsGraphQLAndMapsAnimeMovie() async throws {
        let service = makeService(response: """
        {
          "data": {
            "Page": {
              "media": [{
                "id": 199,
                "title": {
                  "romaji": "Sen to Chihiro no Kamikakushi",
                  "english": "Spirited Away",
                  "native": "千と千尋の神隠し"
                },
                "synonyms": ["Атака духов"],
                "format": "MOVIE",
                "description": "<b>A young girl</b> enters a spirit world.",
                "startDate": { "year": 2001, "month": 7, "day": 20 },
                "duration": 125,
                "coverImage": {
                  "extraLarge": "https://example.com/cover-xl.jpg",
                  "large": "https://example.com/cover-large.jpg",
                  "medium": "https://example.com/cover-medium.jpg"
                },
                "bannerImage": "https://example.com/banner.jpg",
                "genres": ["Adventure", "Drama"],
                "averageScore": 88,
                "popularity": 910000
              }]
            }
          }
        }
        """)

        let results = try await service.search(
            title: "Spirited Away",
            year: 2001,
            kind: .movie,
            language: "ru-RU"
        )

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.id, "199")
        XCTAssertEqual(result.provider, .anilist)
        XCTAssertEqual(result.kind, .movie)
        XCTAssertEqual(result.localizedTitle, "Spirited Away")
        XCTAssertEqual(result.originalTitle, "Sen to Chihiro no Kamikakushi")
        XCTAssertEqual(result.releaseDate, "2001-07-20")
        XCTAssertEqual(result.overview, "A young girl enters a spirit world.")
        XCTAssertEqual(result.rating, 8.8)
        XCTAssertEqual(result.posterURL?.absoluteString, "https://example.com/cover-xl.jpg")
        XCTAssertEqual(result.backdropURL?.absoluteString, "https://example.com/banner.jpg")

        let request = try XCTUnwrap(AniListURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://graphql.anilist.co")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(AniListURLProtocol.capturedBodies.first)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertTrue((payload["query"] as? String)?.contains("type: ANIME") == true)
        XCTAssertEqual(
            (payload["variables"] as? [String: Any])?["search"] as? String,
            "Spirited Away"
        )
    }

    func testDetailsMapsSeriesMetadata() async throws {
        let service = makeService(response: """
        {
          "data": {
            "Media": {
              "id": 16498,
              "title": {
                "romaji": "Shingeki no Kyojin",
                "english": "Attack on Titan",
                "native": "進撃の巨人"
              },
              "synonyms": [],
              "format": "TV",
              "description": "Humanity fights for survival.<br>Beyond the walls.",
              "startDate": { "year": 2013, "month": 4, "day": 7 },
              "duration": 24,
              "coverImage": {
                "extraLarge": null,
                "large": "https://example.com/aot.jpg",
                "medium": null
              },
              "bannerImage": "https://example.com/aot-banner.jpg",
              "genres": ["Action", "Drama", "Fantasy"],
              "averageScore": 84,
              "popularity": 800000
            }
          }
        }
        """)

        let metadata = try await service.details(
            id: "16498",
            kind: .tv,
            language: "ru-RU"
        )

        XCTAssertEqual(metadata.provider, .anilist)
        XCTAssertEqual(metadata.kind, .tv)
        XCTAssertEqual(metadata.localizedTitle, "Attack on Titan")
        XCTAssertEqual(metadata.originalTitle, "Shingeki no Kyojin")
        XCTAssertEqual(metadata.runtimeMinutes, 24)
        XCTAssertEqual(metadata.releaseDate, "2013-04-07")
        XCTAssertEqual(metadata.rating, 8.4)
        XCTAssertEqual(metadata.genres, ["Action", "Drama", "Fantasy"])
        XCTAssertEqual(metadata.posterURL?.absoluteString, "https://example.com/aot.jpg")
        XCTAssertEqual(metadata.backdropURL?.absoluteString, "https://example.com/aot-banner.jpg")
        XCTAssertTrue(metadata.overview.contains("Beyond the walls."))

        let body = try XCTUnwrap(AniListURLProtocol.capturedBodies.first)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual((payload["variables"] as? [String: Any])?["id"] as? Int, 16498)
    }

    func testResolverRejectsPartialAniListTitleMatch() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = MetadataResolver(
            services: [PartialAniListService()],
            cache: MetadataCache(fileURL: directory.appendingPathComponent("cache.json"))
        )

        let outcome = await resolver.resolve(
            candidates: ["Naruto.S01E01.1080p.mkv"],
            provider: .anilist,
            language: "ru-RU"
        )

        XCTAssertEqual(outcome, .notFound)
    }

    private func makeService(response: String) -> AniListService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AniListURLProtocol.self]
        AniListURLProtocol.responseData = Data(response.utf8)
        AniListURLProtocol.capturedRequests = []
        AniListURLProtocol.capturedBodies = []
        return AniListService(session: URLSession(configuration: configuration))
    }
}

private struct PartialAniListService: MetadataServicing {
    let provider = MetadataProvider.anilist

    func search(
        title: String,
        year: Int?,
        kind: MediaKind,
        language: String
    ) async throws -> [MediaSearchResult] {
        [MediaSearchResult(
            id: "17",
            provider: .anilist,
            kind: .tv,
            localizedTitle: "Naruto: Shippuden",
            originalTitle: "Naruto: Shippuuden",
            releaseDate: "2007-02-15",
            posterURL: nil,
            backdropURL: nil,
            overview: "",
            rating: 8.1,
            popularity: 100
        )]
    }

    func details(
        id: String,
        kind: MediaKind,
        language: String
    ) async throws -> MediaMetadata {
        XCTFail("Details must not be requested for a partial AniList match")
        throw MetadataServiceError.invalidRequest
    }
}

private final class AniListURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData: Data?
    static var capturedRequests: [URLRequest] = []
    static var capturedBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequests.append(request)
        if let body = request.httpBody ?? request.httpBodyStream?.readAllData() {
            Self.capturedBodies.append(body)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while hasBytesAvailable {
            let count = read(buffer, maxLength: 4096)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

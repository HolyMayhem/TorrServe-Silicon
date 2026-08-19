import Foundation
import XCTest
@testable import TorrServerKit

final class KinopoiskServiceTests: XCTestCase {
    func testSearchMapsMovieAndSendsAPIKeyHeader() async throws {
        let service = makeService(response: """
        {
          "total": 1,
          "totalPages": 1,
          "items": [{
            "kinopoiskId": 301,
            "nameRu": "Матрица",
            "nameEn": "The Matrix",
            "nameOriginal": "The Matrix",
            "ratingKinopoisk": 8.5,
            "ratingImdb": 8.7,
            "year": 1999,
            "type": "FILM",
            "posterUrl": "https://example.com/matrix.jpg"
          }]
        }
        """)

        let results = try await service.search(
            title: "The Matrix",
            year: 1999,
            kind: .movie,
            language: "ru-RU"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "301")
        XCTAssertEqual(results.first?.provider, .kinopoisk)
        XCTAssertEqual(results.first?.kind, .movie)
        XCTAssertEqual(results.first?.localizedTitle, "Матрица")
        XCTAssertEqual(results.first?.originalTitle, "The Matrix")
        XCTAssertEqual(results.first?.releaseYear, 1999)
        XCTAssertEqual(results.first?.rating, 8.5)
        XCTAssertEqual(
            KinopoiskURLProtocol.capturedRequest?.value(forHTTPHeaderField: "X-API-KEY"),
            "test-key"
        )

        let components = KinopoiskURLProtocol.capturedRequest?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        XCTAssertTrue(components?.queryItems?.contains(
            URLQueryItem(name: "keyword", value: "The Matrix")
        ) == true)
        XCTAssertTrue(components?.queryItems?.contains(
            URLQueryItem(name: "yearFrom", value: "1999")
        ) == true)
        XCTAssertTrue(components?.queryItems?.contains(
            URLQueryItem(name: "yearTo", value: "1999")
        ) == true)
    }

    func testDetailsMapsSeriesMetadata() async throws {
        let service = makeService(response: """
        {
          "kinopoiskId": 464963,
          "nameRu": "Игра престолов",
          "nameEn": "Game of Thrones",
          "nameOriginal": "Game of Thrones",
          "posterUrl": "https://example.com/poster.jpg",
          "coverUrl": "https://example.com/cover.jpg",
          "ratingKinopoisk": 9.0,
          "ratingImdb": 9.2,
          "year": 2011,
          "filmLength": 55,
          "description": "Борьба за Железный трон.",
          "shortDescription": "Фэнтези-сериал.",
          "type": "TV_SERIES",
          "genres": [{"genre": "фэнтези"}, {"genre": "драма"}]
        }
        """)

        let metadata = try await service.details(
            id: "464963",
            kind: .tv,
            language: "ru-RU"
        )

        XCTAssertEqual(metadata.provider, .kinopoisk)
        XCTAssertEqual(metadata.kind, .tv)
        XCTAssertEqual(metadata.localizedTitle, "Игра престолов")
        XCTAssertEqual(metadata.originalTitle, "Game of Thrones")
        XCTAssertEqual(metadata.overview, "Борьба за Железный трон.")
        XCTAssertEqual(metadata.genres, ["фэнтези", "драма"])
        XCTAssertEqual(metadata.runtimeMinutes, 55)
        XCTAssertEqual(metadata.releaseDate, "2011")
        XCTAssertEqual(metadata.rating, 9.0)
        XCTAssertEqual(metadata.posterURL?.absoluteString, "https://example.com/poster.jpg")
        XCTAssertEqual(metadata.backdropURL?.absoluteString, "https://example.com/cover.jpg")
    }

    private func makeService(response: String) -> KinopoiskService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KinopoiskURLProtocol.self]
        KinopoiskURLProtocol.responseData = Data(response.utf8)
        KinopoiskURLProtocol.capturedRequest = nil
        return KinopoiskService(
            configurationProvider: KinopoiskConfigurationStub(),
            session: URLSession(configuration: configuration)
        )
    }
}

private struct KinopoiskConfigurationStub: KinopoiskConfigurationProviding {
    func kinopoiskConfiguration() -> KinopoiskConfiguration? {
        KinopoiskConfiguration(
            apiKey: "test-key",
            apiBaseURL: URL(string: "https://example.com")!
        )
    }
}

private final class KinopoiskURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

import Foundation
import XCTest
@testable import TorrServerManager

final class MetadataAPIKeyValidatorTests: XCTestCase {
    override func tearDown() {
        ValidationURLProtocol.handler = nil
        super.tearDown()
    }

    func testTMDBAcceptsSuccessfulAuthenticationResponse() async {
        let validator = makeValidator { request in
            XCTAssertEqual(request.url?.path, "/3/authentication")
            XCTAssertTrue(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(URLQueryItem(name: "api_key", value: "tmdb-test-key")) == true)
            return (200, Data(#"{"success":true}"#.utf8))
        }

        let result = await validator.validate(provider: .tmdb, apiKey: "tmdb-test-key")

        XCTAssertEqual(result, .valid)
    }

    func testTMDBRejectsUnauthorizedKey() async {
        let validator = makeValidator { _ in (401, Data()) }

        let result = await validator.validate(provider: .tmdb, apiKey: "wrong-key")

        XCTAssertEqual(result, .invalid)
    }

    func testOMDBAcceptsSuccessfulLookup() async {
        let validator = makeValidator { request in
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertTrue(queryItems?.contains(URLQueryItem(name: "apikey", value: "omdb-test-key")) == true)
            XCTAssertTrue(queryItems?.contains(URLQueryItem(name: "i", value: "tt0133093")) == true)
            return (200, Data(#"{"Response":"True","Title":"The Matrix"}"#.utf8))
        }

        let result = await validator.validate(provider: .omdb, apiKey: "omdb-test-key")

        XCTAssertEqual(result, .valid)
    }

    func testOMDBRejectsInvalidKeyMessage() async {
        let validator = makeValidator { _ in
            (200, Data(#"{"Response":"False","Error":"Invalid API key!"}"#.utf8))
        }

        let result = await validator.validate(provider: .omdb, apiKey: "wrong-key")

        XCTAssertEqual(result, .invalid)
    }

    func testOMDBReportsAcceptedKeyWithExhaustedQuota() async {
        let validator = makeValidator { _ in
            (200, Data(#"{"Response":"False","Error":"Request limit reached!"}"#.utf8))
        }

        let result = await validator.validate(provider: .omdb, apiKey: "valid-key")

        XCTAssertEqual(result, .rateLimited)
    }

    func testOMDBTreatsNonAuthenticationAPIErrorsAsAcceptedKey() async {
        let validator = makeValidator { _ in
            (200, Data(#"{"Response":"False","Error":"Movie not found!"}"#.utf8))
        }

        let result = await validator.validate(provider: .omdb, apiKey: "valid-key")

        XCTAssertEqual(result, .valid)
    }

    func testKinopoiskSendsKeyInHeader() async {
        let validator = makeValidator { request in
            XCTAssertEqual(request.url?.path, "/api/v2.2/films/301")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "kinopoisk-test-key")
            return (200, Data(#"{"kinopoiskId":301}"#.utf8))
        }

        let result = await validator.validate(
            provider: .kinopoisk,
            apiKey: "kinopoisk-test-key"
        )

        XCTAssertEqual(result, .valid)
    }

    func testServerFailureIsUnavailableRatherThanInvalid() async {
        let validator = makeValidator { _ in (500, Data()) }

        let result = await validator.validate(provider: .kinopoisk, apiKey: "test-key")

        XCTAssertEqual(result, .unavailable)
    }

    private func makeValidator(
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> MetadataAPIKeyValidator {
        ValidationURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ValidationURLProtocol.self]
        return MetadataAPIKeyValidator(session: URLSession(configuration: configuration))
    }
}

private final class ValidationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

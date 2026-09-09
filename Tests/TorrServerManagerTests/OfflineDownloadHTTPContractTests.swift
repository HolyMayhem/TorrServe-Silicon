import Foundation
import XCTest
@testable import TorrServerManager

final class OfflineDownloadHTTPContractTests: XCTestCase {
    private let streamURL = URL(string: "http://127.0.0.1:8090/stream/video.mkv")!
    private let entityTag = #""torrent-hash/video.mkv""#

    func testAcceptsInitialResponseAndCapturesIdentity() throws {
        let response = makeResponse(
            statusCode: 200,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "4096",
                "ETag": entityTag
            ]
        )

        let identity = try OfflineDownloadHTTPContract.validateInitialResponse(
            response,
            expectedLength: 4096
        )

        XCTAssertEqual(
            identity,
            OfflineDownloadStreamIdentity(contentLength: 4096, entityTag: entityTag)
        )
    }

    func testRejectsInitialResponseWithUnexpectedLength() {
        let response = makeResponse(
            statusCode: 200,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "2048",
                "ETag": entityTag
            ]
        )

        XCTAssertThrowsError(
            try OfflineDownloadHTTPContract.validateInitialResponse(
                response,
                expectedLength: 4096
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadHTTPContractError,
                .invalidContentLength(expected: 4096, actual: "2048")
            )
        }
    }

    func testRejectsWeakEntityTag() {
        let response = makeResponse(
            statusCode: 200,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "4096",
                "ETag": #"W/"torrent-hash/video.mkv""#
            ]
        )

        XCTAssertThrowsError(
            try OfflineDownloadHTTPContract.validateInitialResponse(
                response,
                expectedLength: 4096
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadHTTPContractError,
                .missingOrWeakEntityTag
            )
        }
    }

    func testAcceptsOpenEndedResumeResponse() throws {
        let identity = OfflineDownloadStreamIdentity(
            contentLength: 4096,
            entityTag: entityTag
        )
        let response = makeResponse(
            statusCode: 206,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "3072",
                "Content-Range": "bytes 1024-4095/4096",
                "ETag": entityTag
            ]
        )

        let range = try OfflineDownloadHTTPContract.validateResumeResponse(
            response,
            requestedOffset: 1024,
            identity: identity
        )

        XCTAssertEqual(
            range,
            OfflineDownloadByteRange(start: 1024, end: 4095, totalLength: 4096)
        )
    }

    func testRejectsFullResponseWhenResumeWasRequested() {
        let identity = OfflineDownloadStreamIdentity(
            contentLength: 4096,
            entityTag: entityTag
        )
        let response = makeResponse(
            statusCode: 200,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "4096",
                "ETag": entityTag
            ]
        )

        XCTAssertThrowsError(
            try OfflineDownloadHTTPContract.validateResumeResponse(
                response,
                requestedOffset: 1024,
                identity: identity
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadHTTPContractError,
                .serverIgnoredRange
            )
        }
    }

    func testRejectsChangedEntityTag() {
        let identity = OfflineDownloadStreamIdentity(
            contentLength: 4096,
            entityTag: entityTag
        )
        let response = makeResponse(
            statusCode: 206,
            headers: [
                "Accept-Ranges": "bytes",
                "Content-Length": "3072",
                "Content-Range": "bytes 1024-4095/4096",
                "ETag": #""another-file""#
            ]
        )

        XCTAssertThrowsError(
            try OfflineDownloadHTTPContract.validateResumeResponse(
                response,
                requestedOffset: 1024,
                identity: identity
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadHTTPContractError,
                .entityTagChanged(
                    expected: entityTag,
                    actual: #""another-file""#
                )
            )
        }
    }

    func testRejectsUnsatisfiedResumeRange() {
        let identity = OfflineDownloadStreamIdentity(
            contentLength: 4096,
            entityTag: entityTag
        )
        let response = makeResponse(statusCode: 416, headers: [:])

        XCTAssertThrowsError(
            try OfflineDownloadHTTPContract.validateResumeResponse(
                response,
                requestedOffset: 1024,
                identity: identity
            )
        ) { error in
            XCTAssertEqual(
                error as? OfflineDownloadHTTPContractError,
                .rangeNotSatisfiable
            )
        }
    }

    private func makeResponse(
        statusCode: Int,
        headers: [String: String]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: streamURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

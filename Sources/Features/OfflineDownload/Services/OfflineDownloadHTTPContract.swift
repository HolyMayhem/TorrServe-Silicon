import Foundation

struct OfflineDownloadStreamIdentity: Equatable, Sendable {
    let contentLength: Int64
    let entityTag: String
}

struct OfflineDownloadByteRange: Equatable, Sendable {
    let start: Int64
    let end: Int64
    let totalLength: Int64
}

enum OfflineDownloadHTTPContractError: Error, Equatable {
    case invalidExpectedLength(Int64)
    case invalidResumeOffset(offset: Int64, totalLength: Int64)
    case unexpectedStatus(expected: Int, actual: Int)
    case serverIgnoredRange
    case rangeNotSatisfiable
    case byteRangesUnsupported
    case missingOrWeakEntityTag
    case entityTagChanged(expected: String, actual: String?)
    case invalidContentLength(expected: Int64, actual: String?)
    case invalidContentRange(String?)
    case unexpectedContentRange(expected: OfflineDownloadByteRange, actual: OfflineDownloadByteRange)
}

extension OfflineDownloadHTTPContractError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidExpectedLength(let length):
            return "Invalid expected file length: \(length)."
        case .invalidResumeOffset(let offset, let totalLength):
            return "Resume offset \(offset) is outside the file length \(totalLength)."
        case .unexpectedStatus(let expected, let actual):
            return "TorrServer returned HTTP \(actual); expected HTTP \(expected)."
        case .serverIgnoredRange:
            return "TorrServer ignored the byte range and returned the complete file."
        case .rangeNotSatisfiable:
            return "TorrServer rejected the requested byte range."
        case .byteRangesUnsupported:
            return "TorrServer did not advertise byte-range support."
        case .missingOrWeakEntityTag:
            return "TorrServer did not return a strong ETag for the file."
        case .entityTagChanged(let expected, let actual):
            return "The stream ETag changed from \(expected) to \(actual ?? "<missing>")."
        case .invalidContentLength(let expected, let actual):
            return "Invalid Content-Length \(actual ?? "<missing>"); expected \(expected)."
        case .invalidContentRange(let value):
            return "Invalid Content-Range: \(value ?? "<missing>")."
        case .unexpectedContentRange(let expected, let actual):
            return "Unexpected Content-Range \(actual); expected \(expected)."
        }
    }
}

enum OfflineDownloadHTTPContract {
    static func validateInitialResponse(
        _ response: HTTPURLResponse,
        expectedLength: Int64
    ) throws -> OfflineDownloadStreamIdentity {
        guard expectedLength > 0 else {
            throw OfflineDownloadHTTPContractError.invalidExpectedLength(expectedLength)
        }
        guard response.statusCode == 200 else {
            throw OfflineDownloadHTTPContractError.unexpectedStatus(
                expected: 200,
                actual: response.statusCode
            )
        }

        try validateByteRangeSupport(response)
        try validateContentLength(response, expected: expectedLength)

        guard let entityTag = response.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !entityTag.isEmpty,
              !entityTag.lowercased().hasPrefix("w/") else {
            throw OfflineDownloadHTTPContractError.missingOrWeakEntityTag
        }

        return OfflineDownloadStreamIdentity(
            contentLength: expectedLength,
            entityTag: entityTag
        )
    }

    static func validateResumeResponse(
        _ response: HTTPURLResponse,
        requestedOffset: Int64,
        identity: OfflineDownloadStreamIdentity
    ) throws -> OfflineDownloadByteRange {
        guard requestedOffset > 0, requestedOffset < identity.contentLength else {
            throw OfflineDownloadHTTPContractError.invalidResumeOffset(
                offset: requestedOffset,
                totalLength: identity.contentLength
            )
        }

        switch response.statusCode {
        case 206:
            break
        case 200:
            throw OfflineDownloadHTTPContractError.serverIgnoredRange
        case 416:
            throw OfflineDownloadHTTPContractError.rangeNotSatisfiable
        default:
            throw OfflineDownloadHTTPContractError.unexpectedStatus(
                expected: 206,
                actual: response.statusCode
            )
        }

        try validateByteRangeSupport(response)

        let actualEntityTag = response.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard actualEntityTag == identity.entityTag else {
            throw OfflineDownloadHTTPContractError.entityTagChanged(
                expected: identity.entityTag,
                actual: actualEntityTag
            )
        }

        let expectedRange = OfflineDownloadByteRange(
            start: requestedOffset,
            end: identity.contentLength - 1,
            totalLength: identity.contentLength
        )
        let contentRangeValue = response.value(forHTTPHeaderField: "Content-Range")
        guard let actualRange = parseContentRange(contentRangeValue) else {
            throw OfflineDownloadHTTPContractError.invalidContentRange(contentRangeValue)
        }
        guard actualRange == expectedRange else {
            throw OfflineDownloadHTTPContractError.unexpectedContentRange(
                expected: expectedRange,
                actual: actualRange
            )
        }

        try validateContentLength(
            response,
            expected: identity.contentLength - requestedOffset
        )
        return actualRange
    }

    static func parseContentRange(_ value: String?) -> OfflineDownloadByteRange? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.lowercased().hasPrefix("bytes ") else { return nil }

        let rangeAndTotal = normalized.dropFirst("bytes ".count).split(separator: "/")
        guard rangeAndTotal.count == 2,
              let totalLength = Int64(rangeAndTotal[1]) else {
            return nil
        }

        let bounds = rangeAndTotal[0].split(separator: "-")
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              start >= 0,
              end >= start,
              totalLength > end else {
            return nil
        }

        return OfflineDownloadByteRange(
            start: start,
            end: end,
            totalLength: totalLength
        )
    }

    private static func validateByteRangeSupport(_ response: HTTPURLResponse) throws {
        let values = response.value(forHTTPHeaderField: "Accept-Ranges")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard values?.contains("bytes") == true else {
            throw OfflineDownloadHTTPContractError.byteRangesUnsupported
        }
    }

    private static func validateContentLength(
        _ response: HTTPURLResponse,
        expected: Int64
    ) throws {
        let value = response.value(forHTTPHeaderField: "Content-Length")
        guard value.flatMap(Int64.init) == expected else {
            throw OfflineDownloadHTTPContractError.invalidContentLength(
                expected: expected,
                actual: value
            )
        }
    }
}

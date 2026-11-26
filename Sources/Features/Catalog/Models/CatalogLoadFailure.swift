import Foundation

struct CatalogLoadFailure: Error, Hashable {
    let attempts: [Attempt]

    struct Attempt: Hashable {
        let source: CatalogSource
        let reason: Reason
    }

    enum Reason: Error, Hashable {
        case simulated
        case offline
        case dns
        case connection
        case timeout
        case secureConnection
        case missingKey
        case invalidRequest
        case accessDenied(Int)
        case rateLimited
        case serviceError(Int)
        case unexpectedHTTPStatus(Int)
        case invalidResponse
        case otherNetworkError(Int)
        case unknown

        init(_ error: Error) {
            switch error {
            case let reason as Self:
                self = reason
            case let error as URLError:
                switch error.code {
                case .notConnectedToInternet: self = .offline
                case .cannotFindHost, .dnsLookupFailed: self = .dns
                case .cannotConnectToHost, .networkConnectionLost: self = .connection
                case .timedOut: self = .timeout
                case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                     .clientCertificateRejected, .clientCertificateRequired:
                    self = .secureConnection
                case .badURL, .unsupportedURL: self = .invalidRequest
                default: self = .otherNetworkError(error.code.rawValue)
                }
            case let error as MetadataServiceError:
                switch error {
                case .notConfigured: self = .missingKey
                case .invalidRequest: self = .invalidRequest
                case .invalidResponse, .decodingFailed, .api: self = .invalidResponse
                case .httpStatus(let status):
                    switch status {
                    case 401, 403, 451: self = .accessDenied(status)
                    case 429: self = .rateLimited
                    case 500...599: self = .serviceError(status)
                    default: self = .unexpectedHTTPStatus(status)
                    }
                }
            default:
                self = .unknown
            }
        }
    }
}

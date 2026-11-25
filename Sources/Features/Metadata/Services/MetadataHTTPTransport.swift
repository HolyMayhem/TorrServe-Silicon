import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MetadataHTTPTransport {
    static func data(
        for request: URLRequest,
        session: URLSession,
        allowsSecureDNS: Bool = false
    ) async throws -> Data {
        let data: Data
        let status: Int
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MetadataServiceError.invalidResponse
            }
            (data, status) = (body, http.statusCode)
        } catch {
            guard allowsSecureDNS, TMDBSecureDNS.canRetry(request, after: error) else { throw error }
            try Task.checkCancellation()
            (data, status) = try await TMDBSecureDNS.shared.data(for: request)
        }
        guard (200...299).contains(status) else {
            throw MetadataServiceError.httpStatus(status)
        }
        return data
    }

    static func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed
        }
    }
}

import Foundation

enum MetadataHTTPTransport {
    static func data(
        for request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MetadataServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw MetadataServiceError.httpStatus(http.statusCode)
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

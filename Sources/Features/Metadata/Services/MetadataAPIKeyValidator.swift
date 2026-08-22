import Foundation

enum MetadataAPIKeyValidationResult: Equatable, Sendable {
    case valid
    case invalid
    case rateLimited
    case unavailable
}

actor MetadataAPIKeyValidator {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(
        provider: MetadataProvider,
        apiKey: String
    ) async -> MetadataAPIKeyValidationResult {
        guard provider.requiresAPIKey else { return .valid }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .invalid }

        do {
            switch provider {
            case .tmdb:
                return try await validateTMDB(key)
            case .omdb:
                return try await validateOMDB(key)
            case .kinopoisk:
                return try await validateKinopoisk(key)
            case .anilist:
                return .valid
            }
        } catch {
            return .unavailable
        }
    }

    private func validateTMDB(_ apiKey: String) async throws -> MetadataAPIKeyValidationResult {
        var components = URLComponents(
            string: "https://api.themoviedb.org/3/authentication"
        )
        components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components?.url else { return .unavailable }

        var request = validationRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        return validationResult(for: response)
    }

    private func validateOMDB(_ apiKey: String) async throws -> MetadataAPIKeyValidationResult {
        var components = URLComponents(string: "https://www.omdbapi.com/")
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: "tt0133093"),
            URLQueryItem(name: "r", value: "json")
        ]
        guard let url = components?.url else { return .unavailable }

        let (data, response) = try await session.data(for: validationRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable
        }
        guard let envelope = try? JSONDecoder().decode(OMDBValidationEnvelope.self, from: data) else {
            return .unavailable
        }
        if envelope.response.caseInsensitiveCompare("True") == .orderedSame {
            return .valid
        }
        let error = envelope.error?.lowercased() ?? ""
        if error.contains("invalid api key")
            || error.contains("no api key")
            || error.contains("api key is invalid")
            || error.contains("not activated") {
            return .invalid
        }
        if error.contains("limit") || error.contains("too many requests") {
            return .rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            return .unavailable
        }

        // Any other structured OMDb response proves that the key was accepted,
        // even when the requested title itself could not be returned.
        return .valid
    }

    private func validateKinopoisk(_ apiKey: String) async throws -> MetadataAPIKeyValidationResult {
        guard let url = URL(string: "https://kinopoiskapiunofficial.tech/api/v2.2/films/301") else {
            return .unavailable
        }
        var request = validationRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        let (_, response) = try await session.data(for: request)
        return validationResult(for: response)
    }

    private func validationRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private func validationResult(for response: URLResponse) -> MetadataAPIKeyValidationResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable
        }
        if (200...299).contains(httpResponse.statusCode) {
            return .valid
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return .invalid
        }
        return .unavailable
    }
}

private struct OMDBValidationEnvelope: Decodable {
    let response: String
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case response = "Response"
        case error = "Error"
    }
}

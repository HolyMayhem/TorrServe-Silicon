import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct JackettRequestScope {
    let baseURL: URL
    private let apiKey: String
    private let basicAuthorization: String?
    private let password: String?
    private let basePath: String

    init?(_ configuration: JackettConfiguration) {
        guard let url = configuration.normalizedServerURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let user = components.user {
            let credentials = "\(user):\(components.password ?? "")"
            basicAuthorization = "Basic " + Data(credentials.utf8).base64EncodedString()
        } else {
            basicAuthorization = nil
        }
        password = components.password
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else { return nil }
        self.baseURL = baseURL
        apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        basePath = components.percentEncodedPath
    }

    func contains(_ url: URL) -> Bool {
        url.scheme?.lowercased() == baseURL.scheme?.lowercased() &&
            url.host?.lowercased() == baseURL.host?.lowercased() &&
            Self.port(url) == Self.port(baseURL)
    }

    func authorize(_ request: inout URLRequest) {
        request.setValue(basicAuthorization, forHTTPHeaderField: "Authorization")
    }

    func resolve(_ link: URL, relativeTo previous: URL?) -> URL? {
        let directory = baseURL.appendingPathComponent("", isDirectory: true)
        guard let resolved = URL(string: link.relativeString, relativeTo: previous ?? directory)?.absoluteURL,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { return nil }

        // Jackett generates /dl/<indexer>?jackett_apikey=… links. Match the route and
        // configured key before treating a loopback or Docker address as Jackett.
        let path = components.percentEncodedPath
        let hasConfiguredKey = !apiKey.isEmpty && components.queryItems?.contains {
            $0.name.lowercased() == "jackett_apikey" && $0.value == apiKey
        } == true
        guard hasConfiguredKey,
              let route = path.range(of: #"/dl/[^/]+$"#, options: .regularExpression),
              // An external redirect must resolve on its own origin.
              previous.map(contains) ?? true,
              let host = components.host?.lowercased(),
              host == baseURL.host?.lowercased() || Self.isInternalAlias(host),
              let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return resolved
        }

        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        components.user = nil
        components.password = nil
        components.percentEncodedPath = basePath + path[route]
        return components.url
    }

    func credentials(in url: URL) -> [String] {
        let names = ["apikey", "api_key", "jackett_apikey", "token", "access_token", "auth", "authorization", "password", "passkey"]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query.filter { names.contains($0.name.lowercased()) }.compactMap(\.value)
    }

    func exposesCredentials(_ url: URL, additionalSecrets: Set<String>) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return true }
        if components.queryItems?.contains(where: { $0.name.lowercased() == "jackett_apikey" }) == true {
            return true
        }
        let values = additionalSecrets.union([apiKey, password, basicAuthorization].compactMap { $0 })
            .filter { !$0.isEmpty }
        var address = url.absoluteString
        while true {
            if values.contains(where: { address.contains($0) }) { return true }
            guard let decoded = address.removingPercentEncoding, decoded != address else { return false }
            address = decoded
        }
    }

    private static func port(_ url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func isInternalAlias(_ host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if ["localhost", "localhost.", "::1", "0.0.0.0", "jackett"].contains(host) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        // Docker bridge addresses can come from any of the private IPv4 ranges.
        return octets[0] == 127 || octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
    }
}

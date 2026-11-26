import Foundation
import os
import TMDBHTTPS

actor TMDBSecureDNS {
    static let shared = TMDBSecureDNS()

    private struct CachedAddresses {
        let values: [String]
        let expires: Date
    }

    private struct DNSResponse: Decodable {
        struct Record: Decodable {
            let type: Int
            let data: String
            let TTL: Int
        }

        let Status: Int
        let TC: Bool
        let Answer: [Record]?
    }

    private var cache: [String: CachedAddresses] = [:]
    private var lookups: [String: Task<[String], Error>] = [:]

    nonisolated static func canRetry(_ request: URLRequest, after error: Error) -> Bool {
        guard let url = request.url, url.scheme == "https", url.port == nil || url.port == 443,
              url.host == "api.themoviedb.org" || url.host == "image.tmdb.org",
              url.user == nil, url.password == nil, request.httpMethod == "GET",
              let error = error as? URLError else { return false }
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
    }

    func data(for request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url, let host = url.host else { throw URLError(.badURL) }
        let addresses = try await addresses(for: host)
        try Task.checkCancellation()
        return try await Self.get(
            url, using: "\(host):443:\(addresses.joined(separator: ","))",
            timeout: request.timeoutInterval,
            limit: 8_000_000
        )
    }

    private func addresses(for host: String) async throws -> [String] {
        if let cached = cache[host], cached.expires > .now { return cached.values }
        if let lookup = lookups[host] { return try await lookup.value }
        let lookup = Task {
            defer { lookups[host] = nil }
            let result = try await Self.resolve(host)
            cache[host] = result
            return result.values
        }
        lookups[host] = lookup
        return try await lookup.value
    }

    private nonisolated static func resolve(_ host: String) async throws -> CachedAddresses {
        var endpoint = URLComponents(string: "https://dns.google/resolve")!
        endpoint.queryItems = [
            URLQueryItem(name: "name", value: host),
            URLQueryItem(name: "type", value: "A"),
            URLQueryItem(name: "edns_client_subnet", value: "0.0.0.0/0")
        ]
        guard let url = endpoint.url else { throw URLError(.badURL) }
        let (data, status) = try await get(url, using: "dns.google:443:8.8.8.8,8.8.4.4", timeout: 4, limit: 16_384)
        guard status == 200, let reply = try? JSONDecoder().decode(DNSResponse.self, from: data),
              reply.Status == 0, !reply.TC, let answers = reply.Answer else {
            throw URLError(.dnsLookupFailed)
        }
        let addresses = answers.filter { $0.type == 1 && isPublicIPv4($0.data) }.map(\.data)
        guard !addresses.isEmpty else { throw URLError(.dnsLookupFailed) }
        let ttl = max(0, min(300, answers.map(\.TTL).min() ?? 0))
        return CachedAddresses(values: addresses, expires: .now.addingTimeInterval(Double(ttl)))
    }

    private nonisolated static func isPublicIPv4(_ address: String) -> Bool {
        let labels = address.split(separator: ".", omittingEmptySubsequences: false)
        let octets = labels.compactMap { UInt8($0) }
        guard labels.count == 4, octets.count == 4,
              octets.map(String.init).joined(separator: ".") == address else { return false }
        let first = octets[0]
        let second = octets[1]
        return first > 0 && first < 224 && first != 10 && first != 127
            && !(first == 169 && second == 254)
            && !(first == 172 && (16...31).contains(second))
            && !(first == 192 && second == 168)
            && !(first == 100 && (64...127).contains(second))
    }

    private final class Transfer: Sendable {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        static let queue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 6
            return queue
        }()
    }

    private nonisolated static func get(
        _ url: URL, using rule: String, timeout: TimeInterval, limit: Int
    ) async throws -> (Data, Int) {
        let transfer = Transfer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Transfer.queue.addOperation {
                    if transfer.cancelled.withLock({ $0 }) {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    var response = TMDBHTTPSResponse()
                    let result = tmdb_https_get(
                        url.absoluteString, rule, Int(max(1, timeout) * 1000), limit,
                        { context in
                            guard let context else { return 1 }
                            let transfer = Unmanaged<Transfer>.fromOpaque(context).takeUnretainedValue()
                            return transfer.cancelled.withLock { $0 ? 1 : 0 }
                        },
                        Unmanaged.passUnretained(transfer).toOpaque(), &response
                    )
                    defer { free(response.bytes) }
                    if transfer.cancelled.withLock({ $0 }) {
                        continuation.resume(throwing: CancellationError())
                    } else if result != 0 {
                        continuation.resume(throwing: URLError(.cannotConnectToHost))
                    } else {
                        let data = response.bytes.map { Data(bytes: $0, count: response.length) } ?? Data()
                        continuation.resume(returning: (data, response.status))
                    }
                }
            }
        } onCancel: {
            transfer.cancelled.withLock { $0 = true }
        }
    }
}

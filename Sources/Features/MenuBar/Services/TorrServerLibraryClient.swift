import Foundation

struct TorrentSummary {
    let title: String
    let size: Int64
    let loadedSize: Int64?
    let seeders: Int
    let activePeers: Int
    let totalPeers: Int
    let status: Int
    let timestamp: Int64
    let downloadSpeed: Double
    let uploadSpeed: Double

    var isActive: Bool {
        downloadSpeed > 0
            || uploadSpeed > 0
            || activePeers > 0
            || (1...3).contains(status)
    }

    var bufferProgress: Double? {
        guard size > 0, let loadedSize else { return nil }
        return min(max(Double(loadedSize) / Double(size), 0), 1)
    }
}

final class TorrServerLibraryClient {
    private let torrentsURL = URL(string: "http://127.0.0.1:8090/torrents")!

    func fetchTorrents(completion: @escaping (Result<[TorrentSummary], Error>) -> Void) {
        var request = URLRequest(url: torrentsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = #"{"action":"list"}"#.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                guard let data else {
                    throw AppError("TorrServer returned no data.")
                }

                let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                let torrents = raw.map(Self.parseTorrent).sorted { left, right in
                    if left.isActive != right.isActive {
                        return left.isActive
                    }
                    return left.timestamp > right.timestamp
                }
                DispatchQueue.main.async { completion(.success(torrents)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private static func parseTorrent(_ dictionary: [String: Any]) -> TorrentSummary {
        let title = stringValue(dictionary["title"])
            ?? stringValue(dictionary["name"])
            ?? stringValue(dictionary["hash"])
            ?? "Torrent"
        let loadedSize = int64Value(value(in: dictionary, keys: [
            "loaded_size", "LoadedSize"
        ]))
        let size = int64Value(value(in: dictionary, keys: [
            "torrent_size", "TorrentSize"
        ]))
            ?? loadedSize
            ?? 0

        return TorrentSummary(
            title: title,
            size: size,
            loadedSize: loadedSize,
            seeders: intValue(value(in: dictionary, keys: [
                "connected_seeders", "ConnectedSeeders"
            ])),
            activePeers: intValue(value(in: dictionary, keys: [
                "active_peers", "ActivePeers"
            ])),
            totalPeers: intValue(value(in: dictionary, keys: [
                "total_peers", "TotalPeers"
            ])),
            status: intValue(value(in: dictionary, keys: [
                "stat", "Stat"
            ])),
            timestamp: int64Value(value(in: dictionary, keys: [
                "timestamp", "Timestamp"
            ])) ?? 0,
            downloadSpeed: doubleValue(value(in: dictionary, keys: [
                "download_speed", "DownloadSpeed"
            ])),
            uploadSpeed: doubleValue(value(in: dictionary, keys: [
                "upload_speed", "UploadSpeed"
            ]))
        )
    }

    private static func value(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dictionary[key] {
                return value
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }
}

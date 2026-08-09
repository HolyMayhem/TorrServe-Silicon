import Foundation

struct NativeTorrentFile: Codable, Hashable, Identifiable {
    let id: Int
    let path: String
    let length: Int64

    var stableID: String { "\(id):\(path)" }
    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }
    var isPlayable: Bool {
        Self.playableExtensions.contains(fileExtension)
    }

    private static let playableExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m2ts",
        "mpg", "mpeg", "flv", "wmv", "mp3", "m4a", "aac", "flac",
        "wav", "ogg", "opus"
    ]

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case length
    }

    init(id: Int, path: String, length: Int64) {
        self.id = id
        self.path = path
        self.length = length
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        length = try container.decodeIfPresent(Int64.self, forKey: .length) ?? 0
    }
}

struct NativeTorrent: Codable, Hashable, Identifiable {
    let title: String
    let category: String
    let poster: String
    let data: String?
    let timestamp: Int64
    let name: String?
    let hash: String
    let stat: Int
    let statString: String
    let loadedSize: Int64
    let torrentSize: Int64
    let preloadedBytes: Int64
    let preloadSize: Int64
    let downloadSpeed: Double
    let uploadSpeed: Double
    let totalPeers: Int
    let activePeers: Int
    let connectedSeeders: Int
    let fileStats: [NativeTorrentFile]

    var id: String {
        hash.isEmpty ? "\(timestamp):\(displayTitle)" : hash
    }

    var displayTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        let fallback = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? "Torrent" : fallback
    }

    var allFiles: [NativeTorrentFile] {
        if !fileStats.isEmpty {
            return fileStats.sorted { $0.id < $1.id }
        }
        return filesFromStoredData.sorted { $0.id < $1.id }
    }

    var playableFiles: [NativeTorrentFile] {
        allFiles.filter(\.isPlayable)
    }

    var isActive: Bool {
        downloadSpeed > 0
            || uploadSpeed > 0
            || activePeers > 0
            || (1...3).contains(stat)
    }

    var progress: Double? {
        guard torrentSize > 0, loadedSize > 0 else { return nil }
        return min(max(Double(loadedSize) / Double(torrentSize), 0), 1)
    }

    var bufferingProgress: Double? {
        guard preloadSize > 0 else { return nil }
        return min(max(Double(preloadedBytes) / Double(preloadSize), 0), 1)
    }

    var resolutionLabel: String? {
        let source = ([displayTitle] + allFiles.map(\.displayName))
            .joined(separator: " ")
            .lowercased()
        if source.contains("2160p") || source.contains("4k") { return "4K" }
        if source.contains("1440p") { return "1440p" }
        if source.contains("1080p") { return "1080p" }
        if source.contains("720p") { return "720p" }
        if source.contains("480p") { return "480p" }
        return nil
    }

    private var filesFromStoredData: [NativeTorrentFile] {
        guard
            let data,
            let jsonData = data.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(StoredTorrentEnvelope.self, from: jsonData)
        else {
            return []
        }
        return envelope.torrServer?.files ?? []
    }

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case poster
        case data
        case timestamp
        case name
        case hash
        case stat
        case statString = "stat_string"
        case loadedSize = "loaded_size"
        case torrentSize = "torrent_size"
        case preloadedBytes = "preloaded_bytes"
        case preloadSize = "preload_size"
        case downloadSpeed = "download_speed"
        case uploadSpeed = "upload_speed"
        case totalPeers = "total_peers"
        case activePeers = "active_peers"
        case connectedSeeders = "connected_seeders"
        case fileStats = "file_stats"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        poster = try container.decodeIfPresent(String.self, forKey: .poster) ?? ""
        data = try container.decodeIfPresent(String.self, forKey: .data)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        hash = try container.decodeIfPresent(String.self, forKey: .hash) ?? ""
        stat = try container.decodeIfPresent(Int.self, forKey: .stat) ?? 0
        statString = try container.decodeIfPresent(String.self, forKey: .statString) ?? ""
        loadedSize = try container.decodeIfPresent(Int64.self, forKey: .loadedSize) ?? 0
        torrentSize = try container.decodeIfPresent(Int64.self, forKey: .torrentSize) ?? 0
        preloadedBytes = try container.decodeIfPresent(Int64.self, forKey: .preloadedBytes) ?? 0
        preloadSize = try container.decodeIfPresent(Int64.self, forKey: .preloadSize) ?? 0
        downloadSpeed = try container.decodeIfPresent(Double.self, forKey: .downloadSpeed) ?? 0
        uploadSpeed = try container.decodeIfPresent(Double.self, forKey: .uploadSpeed) ?? 0
        totalPeers = try container.decodeIfPresent(Int.self, forKey: .totalPeers) ?? 0
        activePeers = try container.decodeIfPresent(Int.self, forKey: .activePeers) ?? 0
        connectedSeeders = try container.decodeIfPresent(Int.self, forKey: .connectedSeeders) ?? 0
        fileStats = try container.decodeIfPresent(
            [NativeTorrentFile].self,
            forKey: .fileStats
        ) ?? []
    }
}

private struct StoredTorrentEnvelope: Decodable {
    let torrServer: StoredTorrentFiles?

    enum CodingKeys: String, CodingKey {
        case torrServer = "TorrServer"
    }
}

private struct StoredTorrentFiles: Decodable {
    let files: [NativeTorrentFile]

    enum CodingKeys: String, CodingKey {
        case files = "Files"
    }
}

struct TorrServerCacheState: Decodable {
    let capacity: Int64
    let filled: Int64
    let hash: String

    enum CodingKeys: String, CodingKey {
        case capacity
        case filled
        case hash
        case capacityUpper = "Capacity"
        case filledUpper = "Filled"
        case hashUpper = "Hash"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capacity = try container.decodeIfPresent(Int64.self, forKey: .capacity)
            ?? container.decodeIfPresent(Int64.self, forKey: .capacityUpper)
            ?? 0
        filled = try container.decodeIfPresent(Int64.self, forKey: .filled)
            ?? container.decodeIfPresent(Int64.self, forKey: .filledUpper)
            ?? 0
        hash = try container.decodeIfPresent(String.self, forKey: .hash)
            ?? container.decodeIfPresent(String.self, forKey: .hashUpper)
            ?? ""
    }
}

struct TorrServerStorageSettings {
    let cacheSize: Int64
    let useDisk: Bool
    let torrentsSavePath: String
    let removeCacheOnDrop: Bool

    init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError("TorrServer returned invalid settings data.")
        }

        func value(_ names: [String]) -> Any? {
            for name in names where object[name] != nil { return object[name] }
            return nil
        }

        cacheSize = (value(["cacheSize", "CacheSize"]) as? NSNumber)?.int64Value ?? 0
        useDisk = (value(["useDisk", "UseDisk"]) as? NSNumber)?.boolValue ?? false
        torrentsSavePath = value(["torrentsSavePath", "TorrentsSavePath"]) as? String ?? ""
        removeCacheOnDrop = (value([
            "removeCacheOnDrop", "RemoveCacheOnDrop"
        ]) as? NSNumber)?.boolValue ?? false
    }
}

import Foundation

final class NativeTorrServerAPI {
    private let baseURL = URL(string: "http://127.0.0.1:8090")!
    private let decoder = JSONDecoder()

    func listTorrents() async throws -> [NativeTorrent] {
        let data = try await postTorrents(["action": "list"])
        return try decoder.decode([NativeTorrent].self, from: data)
            .sorted { left, right in
                if left.isActive != right.isActive {
                    return left.isActive
                }
                return left.timestamp > right.timestamp
            }
    }

    func torrent(hash: String) async throws -> NativeTorrent {
        let data = try await postTorrents([
            "action": "get",
            "hash": hash
        ])
        return try decoder.decode(NativeTorrent.self, from: data)
    }

    func addMagnet(
        _ magnet: String,
        title: String = "",
        poster: String = "",
        category: String = ""
    ) async throws -> NativeTorrent {
        let data = try await postTorrents([
            "action": "add",
            "link": magnet,
            "title": title,
            "poster": poster,
            "category": category,
            "save_to_db": true
        ])
        return try decoder.decode(NativeTorrent.self, from: data)
    }

    func removeTorrent(hash: String) async throws {
        _ = try await postTorrents([
            "action": "rem",
            "hash": hash
        ])
    }

    func dropTorrentCache(hash: String) async throws {
        _ = try await postTorrents([
            "action": "drop",
            "hash": hash
        ])
    }

    func cacheState(hash: String) async throws -> TorrServerCacheState {
        let data = try await post(
            path: "cache",
            body: ["action": "get", "hash": hash],
            timeout: 8
        )
        return try decoder.decode(TorrServerCacheState.self, from: data)
    }

    func settings() async throws -> TorrServerStorageSettings {
        let data = try await post(path: "settings", body: ["action": "get"])
        return try TorrServerStorageSettings(data: data)
    }

    func updateSettings(
        _ draft: TorrServerSettingsDraft,
        basedOn currentSettings: TorrServerStorageSettings
    ) async throws {
        _ = try await post(
            path: "settings",
            body: [
                "action": "set",
                "sets": try currentSettings.payload(applying: draft)
            ]
        )
    }

    func checkHealth() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("echo"))
        request.timeoutInterval = 3
        _ = try await perform(request)
    }

    func uploadTorrent(at fileURL: URL) async throws -> [NativeTorrent] {
        try await uploadTorrent(
            data: Data(contentsOf: fileURL),
            filename: fileURL.lastPathComponent
        )
    }

    func uploadTorrent(
        data fileData: Data,
        filename: String,
        title: String = "",
        poster: String = "",
        category: String = ""
    ) async throws -> [NativeTorrent] {
        let boundary = "TorrServer-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("torrent/upload"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.appendMultipartField(name: "save", value: "true", boundary: boundary)
        if !title.isEmpty {
            body.appendMultipartField(name: "title", value: title, boundary: boundary)
        }
        if !poster.isEmpty {
            body.appendMultipartField(name: "poster", value: poster, boundary: boundary)
        }
        if !category.isEmpty {
            body.appendMultipartField(name: "category", value: category, boundary: boundary)
        }
        body.appendMultipartFile(
            name: "file",
            filename: filename,
            contentType: "application/x-bittorrent",
            data: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let data = try await perform(request)
        if let values = try? decoder.decode([NativeTorrent].self, from: data) {
            return values
        }
        if let value = try? decoder.decode(NativeTorrent.self, from: data) {
            return [value]
        }
        return []
    }

    func updateMetadata(
        hash: String,
        title: String,
        poster: String,
        category: String
    ) async throws {
        _ = try await postTorrents([
            "action": "set",
            "hash": hash,
            "title": title,
            "poster": poster,
            "category": category
        ])
    }

    func streamURL(torrent: NativeTorrent, file: NativeTorrentFile) -> URL? {
        var url = baseURL
            .appendingPathComponent("stream")
            .appendingPathComponent(file.displayName)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "link", value: torrent.hash),
            URLQueryItem(name: "index", value: String(file.id)),
            URLQueryItem(name: "play", value: nil)
        ]
        url = components?.url ?? url
        return url
    }

    func beginPreloading(torrentHash: String, fileID: Int) async {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("stream"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "link", value: torrentHash),
            URLQueryItem(name: "index", value: String(fileID)),
            URLQueryItem(name: "preload", value: nil)
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        _ = try? await URLSession.shared.data(for: request)
    }

    private func postTorrents(_ body: [String: Any]) async throws -> Data {
        try await post(path: "torrents", body: body)
    }

    private func post(
        path: String,
        body: [String: Any],
        timeout: TimeInterval = 15
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError(
                message?.isEmpty == false
                    ? message!
                    : "TorrServer returned HTTP \(status)."
            )
        }
        return data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(
        name: String,
        value: String,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; "
                + "filename=\"\(filename)\"\r\n"
        )
        append("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}

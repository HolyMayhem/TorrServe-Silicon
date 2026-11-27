import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol TorrServerServing {
    func listTorrents() async throws -> [NativeTorrent]
    func torrent(hash: String) async throws -> NativeTorrent
    func addMagnet(
        _ magnet: String,
        title: String,
        poster: String,
        category: String
    ) async throws -> NativeTorrent
    func removeTorrent(hash: String) async throws
    func dropTorrentCache(hash: String) async throws
    func cacheState(hash: String) async throws -> TorrServerCacheState
    func settings() async throws -> TorrServerStorageSettings
    func updateSettings(
        _ draft: TorrServerSettingsDraft,
        basedOn currentSettings: TorrServerStorageSettings
    ) async throws
    func checkHealth() async throws
    func uploadTorrent(at fileURL: URL) async throws -> [NativeTorrent]
    func uploadTorrent(
        data fileData: Data,
        filename: String,
        title: String,
        poster: String,
        category: String
    ) async throws -> [NativeTorrent]
    func updateMetadata(
        hash: String,
        title: String,
        poster: String,
        category: String
    ) async throws
    func streamURL(torrent: NativeTorrent, file: NativeTorrentFile) -> URL?
    func beginPreloading(torrentHash: String, fileID: Int) async
}

extension TorrServerServing {
    func addMagnet(
        _ magnet: String,
        title: String = "",
        poster: String = "",
        category: String = ""
    ) async throws -> NativeTorrent {
        try await addMagnet(
            magnet,
            title: title,
            poster: poster,
            category: category
        )
    }

    func uploadTorrent(
        data fileData: Data,
        filename: String,
        title: String = "",
        poster: String = "",
        category: String = ""
    ) async throws -> [NativeTorrent] {
        try await uploadTorrent(
            data: fileData,
            filename: filename,
            title: title,
            poster: poster,
            category: category
        )
    }
}

final class NativeTorrServerAPI: TorrServerServing {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8090")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func listTorrents() async throws -> [NativeTorrent] {
        let response = try await postTorrents(["action": "list"])
        return try decode(response, endpoint: .torrents) { try decoder.decode([NativeTorrent].self, from: $0) }
            .sorted { left, right in
                if left.isActive != right.isActive {
                    return left.isActive
                }
                return left.timestamp > right.timestamp
            }
    }

    func torrent(hash: String) async throws -> NativeTorrent {
        let response = try await postTorrents([
            "action": "get",
            "hash": hash
        ])
        return try decode(response, endpoint: .torrents) { try decoder.decode(NativeTorrent.self, from: $0) }
    }

    func addMagnet(
        _ magnet: String,
        title: String = "",
        poster: String = "",
        category: String = ""
    ) async throws -> NativeTorrent {
        let response = try await post(path: "torrents", body: [
            "action": "add",
            "link": magnet,
            "title": title,
            "poster": poster,
            "category": category,
            "save_to_db": true
        ], additionLink: "magnet")
        guard let torrent = try decode(response, endpoint: .torrents, using: addedTorrents).first else {
            throw TorrentAddError.noAddedTorrent
        }
        return torrent
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
        let response = try await post(
            path: "cache",
            body: ["action": "get", "hash": hash],
            timeout: 8
        )
        return try decode(response, endpoint: .cache) { try decoder.decode(TorrServerCacheState.self, from: $0) }
    }

    func settings() async throws -> TorrServerStorageSettings {
        let response = try await post(path: "settings", body: ["action": "get"])
        return try decode(response, endpoint: .settings, using: TorrServerStorageSettings.init(data:))
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
        _ = try await healthVersion()
    }

    func healthVersion() async throws -> TorrServerVersion {
        var request = URLRequest(url: baseURL.appendingPathComponent("echo"))
        request.timeoutInterval = 3
        let response = try await perform(request)
        return try decode(response, endpoint: .echo) { data in
            guard let text = String(data: data, encoding: .utf8),
                  let version = TorrServerVersion(releaseTag: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TorrServerBackendError.unexpectedVersion
            }
            TorrServerLocalLog.shared.record(.http, endpoint: .echo, status: response.status, event: .connected)
            return version
        }
    }

    func uploadTorrent(at fileURL: URL) async throws -> [NativeTorrent] {
        let data = try Data(contentsOf: fileURL)
        try TorrentFileValidator.validate(data)
        return try await uploadTorrent(data: data, filename: fileURL.lastPathComponent)
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

        let response = try await perform(request, additionLink: "torrent")
        return try decode(response, endpoint: .upload, using: addedTorrents)
    }

    private func addedTorrents(from data: Data) throws -> [NativeTorrent] {
        let values: [NativeTorrent]?
        do {
            values = try JSONDecoder().decode(TorrServerAddResponse.self, from: data).torrents
        } catch is DecodingError {
            throw TorrentAddError.unexpectedResponse
        }
        // TorrServer can send JSON null when none of the uploaded files were added.
        guard let values, !values.isEmpty else { throw TorrentAddError.noAddedTorrent }
        guard values.allSatisfy({ !$0.hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TorrentAddError.unexpectedResponse
        }
        return values
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
        _ = try? await session.data(for: request)
    }

    private struct Response {
        let data: Data
        let status: Int
    }

    private func decode<T>(
        _ response: Response, endpoint: TorrServerLocalLog.Endpoint, using parse: (Data) throws -> T
    ) throws -> T {
        do {
            return try parse(response.data)
        } catch {
            TorrServerLocalLog.shared.record(.decode, endpoint: endpoint, status: response.status, error: error)
            throw error
        }
    }

    private func postTorrents(_ body: [String: Any]) async throws -> Response {
        try await post(path: "torrents", body: body)
    }

    private func post(
        path: String,
        body: [String: Any],
        timeout: TimeInterval = 15,
        additionLink: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, additionLink: additionLink)
    }

    private func perform(_ request: URLRequest, additionLink: String? = nil) async throws -> Response {
        let endpoint = request.url.flatMap { TorrServerLocalLog.Endpoint(rawValue: $0.lastPathComponent) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if !Task.isCancelled {
                TorrServerLocalLog.shared.record(.http, endpoint: endpoint, error: error)
            }
            guard additionLink != nil else { throw error }
            try Task.checkCancellation()
            throw TorrentAddError.transferNetwork((error as NSError).code)
        }

        let status = (response as? HTTPURLResponse)?.statusCode
        if status.map({ !(200..<300).contains($0) }) ?? true {
            TorrServerLocalLog.shared.record(
                .http, endpoint: endpoint, status: status, error: TorrServerBackendError.invalidHTTPResponse
            )
        }
        if let additionLink {
            guard let http = response as? HTTPURLResponse else { throw TorrentAddError.unexpectedResponse }
            TorrentAddDiagnostics.event(stage: "transfer", source: "TorrServer", link: additionLink, status: http.statusCode)
            guard 200..<300 ~= http.statusCode else { throw TorrentAddError.transferHTTP(http.statusCode) }
            return Response(data: data, status: http.statusCode)
        }
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
        return Response(data: data, status: httpResponse.statusCode)
    }
}

private struct TorrServerAddResponse: Decodable {
    let torrents: [NativeTorrent]?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            torrents = nil
            return
        }
        // Detect the shape independently so a malformed array element remains a decoding error.
        let array: UnkeyedDecodingContainer
        do {
            array = try decoder.unkeyedContainer()
        } catch DecodingError.typeMismatch {
            torrents = [try value.decode(NativeTorrent.self)]
            return
        }
        var items = array
        var results: [NativeTorrent] = []
        while !items.isAtEnd {
            results.append(try items.decode(NativeTorrent.self))
        }
        torrents = results
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

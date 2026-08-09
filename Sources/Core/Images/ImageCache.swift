import AppKit
import CryptoKit
import Foundation
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let session: URLSession

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TorrServer", isDirectory: true)
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
        self.session = session
        memory.countLimit = 120
    }

    func image(for url: URL) async throws -> NSImage {
        if let image = memory.object(forKey: url as NSURL) {
            return image
        }

        if let diskURL = diskURL(for: url),
           let data = try? Data(contentsOf: diskURL),
           let image = NSImage(data: data) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw MetadataServiceError.httpStatus(http.statusCode)
        }
        guard let image = NSImage(data: data) else {
            throw MetadataServiceError.invalidResponse
        }

        memory.setObject(image, forKey: url as NSURL)
        if let diskURL = diskURL(for: url) {
            try? fileManager.createDirectory(
                at: diskURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: diskURL, options: .atomic)
        }
        return image
    }

    func previewURL(for url: URL, title: String) async throws -> URL {
        guard let directoryURL else {
            throw MetadataServiceError.invalidResponse
        }
        let previewDirectory = directoryURL.appendingPathComponent(
            "QuickLook",
            isDirectory: true
        )
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let filename = sanitizedFilename(title)
        let previewURL = previewDirectory.appendingPathComponent(
            "\(filename)-\(digest).png"
        )
        if fileManager.fileExists(atPath: previewURL.path) {
            return previewURL
        }

        let image = try await image(for: url)
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:]) else {
            throw MetadataServiceError.invalidResponse
        }

        try fileManager.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true
        )
        try pngData.write(to: previewURL, options: .atomic)
        return previewURL
    }

    private func diskURL(for url: URL) -> URL? {
        guard let directoryURL else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileExtension = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return directoryURL.appendingPathComponent("\(digest).\(fileExtension)")
    }

    private func sanitizedFilename(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(
                of: #"[^\p{L}\p{N} ._-]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Poster" : cleaned).prefix(72))
    }
}

@MainActor
final class CachedImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = false

    private let cache: ImageCache

    init(cache: ImageCache = .shared) {
        self.cache = cache
    }

    func load(_ url: URL?) async {
        image = nil
        guard let url else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }
        image = try? await cache.image(for: url)
    }
}

struct CachedRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSystemImage = "film"

    @StateObject private var loader = CachedImageLoader()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.16),
                    Color.secondary.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loader.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) {
            await loader.load(url)
        }
    }
}

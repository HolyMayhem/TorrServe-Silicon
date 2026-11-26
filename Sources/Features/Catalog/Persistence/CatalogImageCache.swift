import CoreGraphics
import Foundation
import ImageIO

actor CatalogImageCache {
    static let shared = CatalogImageCache()

    struct Artwork: @unchecked Sendable {
        let image: CGImage
    }

    private final class Entry {
        let artwork: Artwork

        init(_ image: CGImage) { artwork = Artwork(image: image) }
    }

    private let memory = NSCache<NSString, Entry>()
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 48 * 1024 * 1024
        memory.countLimit = 220
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("TorrServer/CatalogImages", isDirectory: true)
        )
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
    }

    func artwork(for url: URL, mirror: URL?) async throws -> Artwork {
        let key = "\(url.absoluteString)\n\(mirror?.absoluteString ?? "")" as NSString
        if let entry = memory.object(forKey: key) { return entry.artwork }
        let image: CGImage
        do {
            image = try await load(url, maxPixelSize: Self.pixelLimit(url))
        } catch {
            try Task.checkCancellation()
            guard let mirror, let fallback = Self.mirroredURL(for: url, using: mirror), fallback != url else { throw error }
            image = try await load(fallback, maxPixelSize: Self.pixelLimit(url))
        }
        try Task.checkCancellation()
        let entry = Entry(image)
        memory.setObject(entry, forKey: key, cost: image.bytesPerRow * image.height)
        return entry.artwork
    }

    private func load(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        let request = URLRequest(url: url, timeoutInterval: 10)
        let data = try await MetadataHTTPTransport.data(for: request, session: session, allowsSecureDNS: true)
        try Task.checkCancellation()
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw MetadataServiceError.invalidResponse
        }
        return image
    }

    private static func pixelLimit(_ url: URL) -> Int {
        switch url.deletingLastPathComponent().lastPathComponent {
        case "w185": return 280
        case "w342": return 520
        default: return 1080
        }
    }

    private static func mirroredURL(for url: URL, using mirror: URL) -> URL? {
        guard url.host == "image.tmdb.org", url.path.hasPrefix("/t/p/") else { return nil }
        return mirror.appendingPathComponent(String(url.path.dropFirst()))
    }
}

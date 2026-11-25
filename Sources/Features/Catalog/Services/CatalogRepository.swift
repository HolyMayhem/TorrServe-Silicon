import Foundation

struct CatalogBrowsePage: Sendable {
    let page: CatalogPage
    let source: CatalogSource
}

struct CatalogRepository: Sendable {
    var tmdb = TMDBCatalogService(tmdb: TMDBService())
    var cub = CUBCatalogService()
    private let cache = CatalogCache()

    func page(
        _ listing: CatalogListing, number: Int, language: String,
        connection: CatalogConnection, preferredSource: CatalogSource? = nil, refresh: Bool = false
    ) async throws -> CatalogBrowsePage {
        let source: CatalogSource = (preferredSource ?? connection.source) == .cub ? .cub : .tmdb
        let key = CatalogCache.Key.page(listing, number, language, source, source == .cub ? connection : nil)
        do {
            return try await load(
                listing, number: number, language: language, source: source, connection: connection, key: key, refresh: refresh
            )
        } catch {
            try Task.checkCancellation()
            guard (error as? URLError)?.code != .cancelled else { throw error }
            if source == .tmdb, connection.source == .auto {
                // The providers have different page boundaries. Start at CUB's first page.
                let fallbackKey = CatalogCache.Key.page(listing, 1, language, .cub, connection)
                do {
                    return try await load(
                        listing, number: 1, language: language, source: .cub, connection: connection, key: fallbackKey, refresh: refresh
                    )
                } catch {
                    try Task.checkCancellation()
                    if case .page(let page) = await cache.value(for: fallbackKey, allowingStale: true) {
                        return CatalogBrowsePage(page: page, source: .cub)
                    }
                }
            }
            if case .page(let page) = await cache.value(for: key, allowingStale: true) {
                return CatalogBrowsePage(page: page, source: source)
            }
            throw error
        }
    }

    func details(_ identity: CatalogIdentity, language: String, timeout: TimeInterval) async throws -> CatalogDetails {
        let key = CatalogCache.Key.details(identity, language)
        if case .details(let result) = await cache.value(for: key) { return result }
        do {
            let result = try await tmdb.details(for: identity, language: language, timeout: timeout)
            try Task.checkCancellation()
            await cache.save(.details(result), for: key)
            return result
        } catch {
            try Task.checkCancellation()
            if case .details(let result) = await cache.value(for: key, allowingStale: true) { return result }
            throw error
        }
    }

    func genres(kind: MediaKind, language: String, timeout: TimeInterval) async throws -> [CatalogGenre] {
        let key = CatalogCache.Key.genres(kind, language)
        if case .genres(let values) = await cache.value(for: key) { return values }
        let values = try await tmdb.genres(kind: kind, language: language, timeout: timeout)
        try Task.checkCancellation()
        await cache.save(.genres(values), for: key)
        return values
    }

    private func load(
        _ listing: CatalogListing, number: Int, language: String,
        source: CatalogSource, connection: CatalogConnection, key: CatalogCache.Key, refresh: Bool
    ) async throws -> CatalogBrowsePage {
        if !refresh, case .page(let page) = await cache.value(for: key) {
            return CatalogBrowsePage(page: page, source: source)
        }
        let page: CatalogPage
        if source == .cub {
            page = try await cub.page(for: listing, page: number, connection: connection)
        } else {
            page = try await tmdb.page(for: listing, page: number, language: language, timeout: connection.timeout)
        }
        try Task.checkCancellation()
        await cache.save(.page(page), for: key)
        return CatalogBrowsePage(page: page, source: source)
    }
}

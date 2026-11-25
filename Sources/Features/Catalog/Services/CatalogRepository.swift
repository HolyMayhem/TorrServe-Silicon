import Foundation

struct CatalogBrowsePage: Sendable {
    let page: CatalogPage
    let source: CatalogSource
}

struct CatalogRepository: Sendable {
    var tmdb = TMDBCatalogService(tmdb: TMDBService())
    var cub = CUBCatalogService()

    func page(
        _ listing: CatalogListing, number: Int, language: String,
        connection: CatalogConnection, preferredSource: CatalogSource? = nil
    ) async throws -> CatalogBrowsePage {
        if (preferredSource ?? connection.source) == .cub {
            return try await cubPage(listing, number: number, connection: connection)
        }
        do {
            let page = try await tmdb.page(for: listing, page: number, language: language, timeout: connection.timeout)
            return CatalogBrowsePage(page: page, source: .tmdb)
        } catch {
            try Task.checkCancellation()
            guard connection.source == .auto, (error as? URLError)?.code != .cancelled else { throw error }
            // A different provider has different page boundaries. Start at its first page.
            return try await cubPage(listing, number: 1, connection: connection)
        }
    }

    func details(_ identity: CatalogIdentity, language: String, timeout: TimeInterval) async throws -> CatalogDetails {
        try await tmdb.details(for: identity, language: language, timeout: timeout)
    }

    private func cubPage(
        _ listing: CatalogListing, number: Int, connection: CatalogConnection
    ) async throws -> CatalogBrowsePage {
        let page = try await cub.page(for: listing, page: number, connection: connection)
        return CatalogBrowsePage(page: page, source: .cub)
    }
}

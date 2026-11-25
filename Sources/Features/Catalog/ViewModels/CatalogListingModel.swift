import SwiftUI

struct CatalogRequest: Hashable, Sendable {
    let listing: CatalogListing
    let language: String
    let connection: CatalogConnection
}

@MainActor
final class CatalogListingModel: ObservableObject {
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var hasMore = false

    private var request: CatalogRequest?
    private var nextPage = 1
    private var source: CatalogSource?
    private var generation = UUID()

    func start(_ request: CatalogRequest, repository: CatalogRepository) async {
        if self.request == request, nextPage > 1 { return }
        self.request = request
        generation = UUID()
        nextPage = 1
        source = nil
        items = []
        hasMore = false
        await load(repository)
    }

    func loadMore(_ repository: CatalogRepository) async {
        guard !loading, failed || hasMore else { return }
        await load(repository)
    }

    private func load(_ repository: CatalogRepository) async {
        guard let request else { return }
        let currentGeneration = generation
        loading = true
        failed = false
        defer { if generation == currentGeneration { loading = false } }

        do {
            // Some providers only support filtering the items in each page.
            // Scan a bounded number of additional pages when a page has no matches.
            for _ in 0..<3 {
                let response = try await repository.page(
                    request.listing, number: nextPage, language: request.language,
                    connection: request.connection, preferredSource: source
                )
                guard !Task.isCancelled, generation == currentGeneration else { return }
                if let source, source != response.source { items = [] }
                source = response.source
                var seen = Set(items.map(\.id))
                let additions = response.page.items.filter { seen.insert($0.id).inserted }
                items += additions
                nextPage = response.page.number + 1
                hasMore = nextPage <= response.page.totalPages
                if !additions.isEmpty || !hasMore { return }
            }
        } catch {
            guard !Task.isCancelled, generation == currentGeneration else { return }
            failed = true
        }
    }
}

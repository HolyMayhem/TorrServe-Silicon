import SwiftUI

struct CatalogRequest: Hashable, Sendable {
    let listing: CatalogListing
    let language: String
    let connection: CatalogConnection
    var revision = 0
}

@MainActor
final class CatalogListingModel: ObservableObject {
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var loading = false
    @Published private(set) var failure: CatalogLoadFailure?
    @Published private(set) var hasMore = false

    private var request: CatalogRequest?
    private var nextPage = 1
    private var source: CatalogSource?
    private var generation = UUID()

    func start(_ request: CatalogRequest, repository: CatalogRepository, retrying: Bool = false) async {
        if self.request == request, retrying {
            await loadMore(repository, for: request)
            return
        }
        if self.request == request, nextPage > 1 { return }
        let refresh = self.request.map { $0.revision != request.revision } ?? (request.revision != 0)
        self.request = request
        generation = UUID()
        nextPage = 1
        source = nil
        items = []
        hasMore = false
        await load(repository, refresh: refresh)
    }

    func loadMore(_ repository: CatalogRepository, for request: CatalogRequest) async {
        guard self.request == request, !loading, failure != nil || hasMore else { return }
        await load(repository)
    }

    private func load(_ repository: CatalogRepository, refresh: Bool = false) async {
        guard let request else { return }
        let currentGeneration = generation
        loading = true
        failure = nil
        defer { if generation == currentGeneration { loading = false } }

        do {
            // Some providers only support filtering the items in each page.
            // Scan a bounded number of additional pages when a page has no matches.
            for _ in 0..<3 {
                let response = try await repository.page(
                    request.listing, number: nextPage, language: request.language,
                    connection: request.connection, preferredSource: source, refresh: refresh
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
            guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled,
                  generation == currentGeneration else { return }
            failure = error as? CatalogLoadFailure ?? CatalogLoadFailure(
                attempts: [.init(source: source ?? (request.connection.source == .cub ? .cub : .tmdb), reason: .init(error))]
            )
        }
    }
}

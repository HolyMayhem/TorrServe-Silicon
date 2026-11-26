import SwiftUI

struct CatalogListingGrid: View {
    let request: CatalogRequest
    let repository: CatalogRepository
    let text: CatalogText
    let openItem: (CatalogItem) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var model = CatalogListingModel()
    @State private var pageRequest: PageRequest?

    private let columns = [GridItem(.adaptive(minimum: 126, maximum: 190), spacing: 16, alignment: .top)]

    private var activePageRequest: PageRequest? {
        isEnabled && pageRequest?.request == request ? pageRequest : nil
    }

    var body: some View {
        Group {
            if let failure = model.failure, model.items.isEmpty {
                CatalogUnavailableView(attempts: failure.attempts, text: text, retry: requestNextPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
        }
        .task(id: request) { await model.start(request, repository: repository) }
        .task(id: activePageRequest) {
            guard let page = activePageRequest else { return }
            await model.loadMore(repository, for: page.request)
            if pageRequest == page { pageRequest = nil }
        }
    }

    private var results: some View {
        CatalogScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(model.items) { item in
                        Button { openItem(item) } label: { CatalogCard(item: item) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("catalog-grid-item")
                    }
                    if model.loading && model.items.isEmpty {
                        ForEach(0..<10) { _ in CatalogSkeleton() }
                    }
                }

                if model.loading && (model.hasMore || !model.items.isEmpty) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 24)
                } else if model.failure != nil {
                    retryFooter
                } else if !model.loading {
                    if model.hasMore {
                        // After a page arrives, the footer's visibility is evaluated at its new position.
                        Color.clear
                            .frame(height: 24)
                            .accessibilityHidden(true)
                            .onScrollVisibilityChange(threshold: 0.5) { visible in
                                if visible { requestNextPage() }
                            }
                            .id(isEnabled)
                    } else if model.items.isEmpty {
                        Text(text("No results on the loaded pages", "На загруженных страницах ничего не найдено"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
        }
    }

    private func requestNextPage() {
        guard isEnabled, pageRequest?.request != request else { return }
        pageRequest = PageRequest(request: request)
    }

    private var retryFooter: some View {
        VStack(spacing: 8) {
            Text(text("Couldn’t load more results", "Не удалось загрузить ещё")).foregroundStyle(.secondary)
            Button(text("Retry", "Повторить"), action: requestNextPage)
        }
        .frame(maxWidth: .infinity)
    }
    private struct PageRequest: Hashable {
        let request: CatalogRequest
        let id = UUID()
    }

}

struct CatalogHomeView: View {
    let repository: CatalogRepository
    let connection: CatalogConnection
    let text: CatalogText
    let revision: Int
    let openCollection: (CatalogCollection) -> Void
    let openItem: (CatalogItem) -> Void
    @State private var failures: [CatalogCollection: ShelfFailure] = [:]
    @State private var retryRevision = 0

    var body: some View {
        if let attempts = outageAttempts {
            CatalogUnavailableView(attempts: attempts, text: text) {
                failures.removeAll()
                retryRevision += 1
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CatalogScrollView {
                // Start the six requests even if the window is too short to show every shelf.
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(CatalogCollection.allCases, id: \.self) { collection in
                        let request = request(for: collection)
                        CatalogShelf(
                            collection: collection, request: request, repository: repository, text: text,
                            openCollection: openCollection, openItem: openItem
                        ) { failure in
                            failures[collection] = failure.map { ShelfFailure(request: request, failure: $0) }
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }

    private func request(for collection: CatalogCollection) -> CatalogRequest {
        CatalogRequest(listing: .collection(collection), language: text.apiLanguage,
                       connection: connection, revision: revision + retryRevision)
    }

    private var outageAttempts: [CatalogLoadFailure.Attempt]? {
        var attempts: [CatalogLoadFailure.Attempt] = []
        var seen = Set<CatalogLoadFailure.Attempt>()
        for collection in CatalogCollection.allCases {
            guard let result = failures[collection], result.request == request(for: collection) else { return nil }
            attempts += result.failure.attempts.filter { seen.insert($0).inserted }
        }
        return attempts
    }

    private struct ShelfFailure {
        let request: CatalogRequest
        let failure: CatalogLoadFailure
    }
}

private struct CatalogShelf: View {
    let collection: CatalogCollection
    let request: CatalogRequest
    let repository: CatalogRepository
    let text: CatalogText
    let openCollection: (CatalogCollection) -> Void
    let openItem: (CatalogItem) -> Void
    let reportFailure: (CatalogLoadFailure?) -> Void
    @StateObject private var model = CatalogListingModel()
    @State private var retry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.title(collection)).font(.title3.weight(.semibold))
                Spacer()
                Button(text("See All", "Смотреть все")) { openCollection(collection) }
            }
            .padding(.horizontal, 20)

            if model.loading || !model.items.isEmpty {
                CatalogScrollView(axis: .horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        if model.items.isEmpty {
                            ForEach(0..<6) { _ in CatalogSkeleton().frame(width: 126) }
                        } else {
                            ForEach(Array(model.items.prefix(16))) { item in
                                Button { openItem(item) } label: { CatalogCard(item: item).frame(width: 126) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                HStack {
                    Text(model.failure != nil ? text("Collection unavailable", "Подборка недоступна") : text("No results", "Нет результатов"))
                        .foregroundStyle(.secondary)
                    if model.failure != nil {
                        Button(text("Retry", "Повторить")) { retry += 1 }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: RetryRequest(request: request, revision: retry)) {
            reportFailure(nil)
            await model.start(request, repository: repository, retrying: retry != 0)
            if !Task.isCancelled { reportFailure(model.items.isEmpty ? model.failure : nil) }
        }
    }

    private struct RetryRequest: Hashable {
        let request: CatalogRequest
        let revision: Int
    }
}

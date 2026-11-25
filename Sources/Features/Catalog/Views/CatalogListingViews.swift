import SwiftUI

struct CatalogListingGrid: View {
    let request: CatalogRequest
    let repository: CatalogRepository
    let text: CatalogText
    let openItem: (CatalogItem) -> Void
    @StateObject private var model = CatalogListingModel()
    @State private var pageRequest: PageRequest?

    private let columns = [GridItem(.adaptive(minimum: 126, maximum: 190), spacing: 16, alignment: .top)]

    var body: some View {
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

                if model.loading && !model.items.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else if model.failed {
                    status(text("Catalog unavailable", "Каталог недоступен"), button: text("Retry", "Повторить"))
                } else if !model.loading {
                    if model.items.isEmpty {
                        Text(text("No results on the loaded pages", "На загруженных страницах ничего не найдено"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    if model.hasMore {
                        status(nil, button: text("Load more", "Загрузить ещё"))
                    }
                }
            }
            .padding(20)
        }
        .task(id: request) { await model.start(request, repository: repository) }
        .task(id: pageRequest?.request == request ? pageRequest : nil) {
            if pageRequest?.request == request { await model.loadMore(repository) }
        }
    }

    private func status(_ message: String?, button: String) -> some View {
        VStack(spacing: 8) {
            if let message { Text(message).foregroundStyle(.secondary) }
            Button(button) { pageRequest = PageRequest(request: request) }
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

    var body: some View {
        CatalogScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(CatalogCollection.allCases, id: \.self) { collection in
                    CatalogShelf(
                        collection: collection, repository: repository, connection: connection, text: text, revision: revision,
                        openCollection: openCollection, openItem: openItem
                    )
                }
            }
            .padding(.vertical, 20)
        }
    }
}

private struct CatalogShelf: View {
    let collection: CatalogCollection
    let repository: CatalogRepository
    let connection: CatalogConnection
    let text: CatalogText
    let revision: Int
    let openCollection: (CatalogCollection) -> Void
    let openItem: (CatalogItem) -> Void
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
                    Text(model.failed ? text("Collection unavailable", "Подборка недоступна") : text("No results", "Нет результатов"))
                        .foregroundStyle(.secondary)
                    if model.failed {
                        Button(text("Retry", "Повторить")) { retry += 1 }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: CatalogRequest(listing: .collection(collection), language: text.apiLanguage, connection: connection, revision: revision)) {
            await model.start(CatalogRequest(listing: .collection(collection), language: text.apiLanguage, connection: connection, revision: revision),
                              repository: repository)
        }
        .task(id: retry) {
            if retry != 0 { await model.loadMore(repository) }
        }
    }
}

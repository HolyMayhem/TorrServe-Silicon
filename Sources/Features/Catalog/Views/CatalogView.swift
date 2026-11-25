import SwiftUI

struct CatalogView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var searchModel: SearchViewModel
    @State private var showsTorrentSearch = false
    @State private var repository = CatalogRepository()
    private let connection = CatalogConnection()

    private var text: CatalogText { CatalogText(language: mainModel.language) }

    var body: some View {
        VStack(spacing: 0) {
            Picker(text("Search mode", "Режим поиска"), selection: $showsTorrentSearch) {
                Text(text("Catalog", "Каталог")).tag(false)
                Text(text("Torrent Search", "Поиск раздач")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            if showsTorrentSearch {
                SearchView(mainModel: mainModel, model: searchModel)
            } else {
                catalog
            }
        }
    }

    private var catalog: some View {
        NavigationStack {
            CatalogHomeView(repository: repository, connection: connection, text: text)
                .navigationDestination(for: CatalogCollection.self) { collection in
                    CatalogListingGrid(
                        request: CatalogRequest(listing: .collection(collection), language: text.apiLanguage, connection: connection),
                        repository: repository, text: text
                    )
                    .navigationTitle(text.title(collection))
                }
                .navigationDestination(for: CatalogItem.self) { item in
                    ScrollView {
                        Text(item.overview).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                    .navigationTitle(item.title)
                }
        }
    }
}

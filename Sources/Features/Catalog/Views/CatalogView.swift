import SwiftUI

struct CatalogView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var searchModel: SearchViewModel
    @State private var showsTorrentSearch = false
    @State private var section = Section.home
    @State private var moviesFilter = CatalogFilter(kind: .movie)
    @State private var seriesFilter = CatalogFilter(kind: .tv)
    @State private var genreFilter = CatalogFilter()
    @State private var path = NavigationPath()
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
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker(text("Category", "Раздел"), selection: $section) {
                    Text(text("Home", "Главная")).tag(Section.home)
                    Text(text("Movies", "Фильмы")).tag(Section.movies)
                    Text(text("TV Shows", "Сериалы")).tag(Section.series)
                    Text(text("Genres", "Жанры")).tag(Section.genres)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                category
            }
                .navigationDestination(for: CatalogCollection.self) { collection in
                    VStack(spacing: 0) {
                        destinationHeader(text.title(collection))
                        grid(.collection(collection))
                    }
                }
                .navigationDestination(for: CatalogItem.self) { item in
                    VStack(spacing: 0) {
                        destinationHeader(item.title)
                        ScrollView {
                            Text(item.overview).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }
                    }
                }
        }
    }
    private enum Section { case home, movies, series, genres }

    @ViewBuilder
    private var category: some View {
        switch section {
        case .home:
            CatalogHomeView(repository: repository, connection: connection, text: text)
        case .movies:
            browse($moviesFilter, kind: .movie)
        case .series:
            browse($seriesFilter, kind: .tv)
        case .genres:
            browse($genreFilter, kind: nil)
        }
    }

    private func browse(_ filter: Binding<CatalogFilter>, kind: MediaKind?) -> some View {
        VStack(spacing: 0) {
            CatalogFiltersView(filter: filter, fixedKind: kind, repository: repository, connection: connection, text: text)
            grid(.discover(filter.wrappedValue))
        }
    }

    private func grid(_ listing: CatalogListing) -> some View {
        CatalogListingGrid(
            request: CatalogRequest(listing: listing, language: text.apiLanguage, connection: connection),
            repository: repository, text: text
        )
    }

    private func destinationHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Label(text("Back", "Назад"), systemImage: "chevron.left")
            }
            Text(title).font(.headline).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

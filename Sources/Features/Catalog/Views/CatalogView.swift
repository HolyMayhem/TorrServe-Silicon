import SwiftUI

struct CatalogView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var searchModel: SearchViewModel
    @State private var showsTorrentSearch = false
    @FocusState private var catalogSearchFocused: Bool
    @State private var searchInput = ""
    @State private var catalogQuery = ""
    @State private var searchFilter = CatalogFilter()
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
        .onChange(of: mainModel.searchFocusRevision) { _, _ in
            if !showsTorrentSearch {
                path = NavigationPath()
                catalogSearchFocused = true
            }
        }
        .onChange(of: mainModel.catalogRefreshRevision) { _, _ in
            if showsTorrentSearch {
                searchModel.search(language: mainModel.language)
            }
        }
    }

    private var catalog: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchBar
                if catalogQuery.isEmpty {
                    categories
                    category
                } else {
                    CatalogFiltersView(filter: $searchFilter, repository: repository, connection: connection, text: text)
                    grid(.search(catalogQuery, searchFilter))
                }
            }
                .task(id: searchInput) {
                    let query = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty {
                        do { try await Task.sleep(for: .milliseconds(300)) }
                        catch { return }
                    }
                    guard !Task.isCancelled else { return }
                    catalogQuery = query
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(text("Search for movies and TV shows", "Поиск фильмов и сериалов"), text: $searchInput)
                .textFieldStyle(.plain)
                .focused($catalogSearchFocused)
                .onSubmit { catalogQuery = searchInput.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !searchInput.isEmpty {
                Button {
                    searchInput = ""
                    catalogQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text("Clear search", "Очистить поиск"))
            }
        }
        .padding(.horizontal, 10)
        .appToolbarControlSurface()
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var categories: some View {
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
    }

    private enum Section { case home, movies, series, genres }

    @ViewBuilder
    private var category: some View {
        switch section {
        case .home:
            CatalogHomeView(repository: repository, connection: connection, text: text, revision: mainModel.catalogRefreshRevision)
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
            request: CatalogRequest(listing: listing, language: text.apiLanguage, connection: connection, revision: mainModel.catalogRefreshRevision),
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

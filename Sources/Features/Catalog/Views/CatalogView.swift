import SwiftUI

struct CatalogView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var searchModel: SearchViewModel
    @ObservedObject var libraryModel: LibraryViewModel
    @State private var showsTorrentSearch = false
    @FocusState private var catalogSearchFocused: Bool
    @State private var searchInput = ""
    @State private var catalogQuery = ""
    @State private var searchFilter = CatalogFilter()
    @State private var section = Section.home
    @State private var moviesFilter = CatalogFilter(kind: .movie)
    @State private var seriesFilter = CatalogFilter(kind: .tv)
    @State private var genreFilter = CatalogFilter()
    @State private var pages: [Page] = []
    @State private var repository = CatalogRepository()
    @ObservedObject private var settings = CatalogSettingsStore.shared
    @Environment(\.settingsSidebarIsVisible) private var isSidebarVisible

    private var connection: CatalogConnection {
        var connection = settings.connection
        connection.tmdb.simulatesOutage = mainModel.simulatesCatalogTMDBOutage
        connection.simulatesCUBOutage = mainModel.simulatesCatalogCUBOutage
        return connection
    }

    private var text: CatalogText { CatalogText(language: mainModel.language) }

    private var showsDetails: Bool {
        guard !showsTorrentSearch, case .item? = pages.last?.destination else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if !showsDetails {
                SettingsPageHeader(
                    title: AppSection.search.title(language: mainModel.language),
                    message: AppSection.search.message(language: mainModel.language)
                )
                .zIndex(1)
                navigationControls
                Divider()
            }

            ZStack {
                catalogPages
                    .environment(\.catalogImageMirror, connection.imageMirror)
                    .modifier(CatalogPageVisibility(isVisible: !showsTorrentSearch))

                if showsTorrentSearch {
                    SearchView(mainModel: mainModel, model: searchModel, libraryModel: libraryModel)
                }
            }
        }
        .toolbar {
            if mainModel.selectedSection == .search, showsDetails {
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .navigation) {
                        detailsBackButton
                            .controlSize(.large)
                            .buttonBorderShape(.circle)
                            .liquidGlassControl()
                            // The expanded split view already adds 8 pt between the toolbar items.
                            .padding(.leading, isSidebarVisible ? 4 : 12)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) { detailsBackButton }
                }
            }
        }
        .onChange(of: searchModel.showsSettings, initial: true) { _, presented in
            if presented { showsTorrentSearch = true }
        }
        .onChange(of: showsTorrentSearch) { _, showing in
            catalogSearchFocused = false
            if !showing { searchModel.endCatalogSearch() }
        }
        .onChange(of: mainModel.selectedSection) { _, section in
            if section != .search { catalogSearchFocused = false }
        }
        .onChange(of: mainModel.searchFocusRevision) { _, _ in
            if mainModel.selectedSection == .search, !showsTorrentSearch {
                pages.removeAll()
                catalogSearchFocused = true
            }
        }
        .onChange(of: mainModel.catalogRefreshRevision) { _, _ in
            if mainModel.selectedSection == .search, showsTorrentSearch {
                searchModel.search(language: mainModel.language)
            }
        }
    }

    private var catalogPages: some View {
        // Retain earlier pages so going back restores their scroll positions and loaded results.
        ZStack {
            catalogRoot.modifier(CatalogPageVisibility(isVisible: pages.isEmpty))
            ForEach(pages) { page in
                destination(page.destination)
                    .modifier(CatalogPageVisibility(isVisible: page.id == pages.last?.id))
            }
        }
    }

    private var catalogRoot: some View {
        VStack(spacing: 0) {
            searchBar
            if catalogQuery.isEmpty {
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
    }

    @ViewBuilder
    private func destination(_ destination: Page.Destination) -> some View {
        switch destination {
        case .collection(let collection):
            VStack(spacing: 0) {
                destinationHeader(text.title(collection))
                grid(.collection(collection))
            }
        case .item(let item):
            CatalogDetailsView(
                item: item, repository: repository, connection: connection, text: text,
                openItem: openItem,
                findTorrents: { context in
                    showsTorrentSearch = true
                    searchModel.searchCatalogTorrents(context, language: mainModel.language)
                }
            )
        }
    }

    private struct Page: Identifiable {
        enum Destination {
            case collection(CatalogCollection)
            case item(CatalogItem)
        }

        let id = UUID()
        let destination: Destination
    }

    private func openItem(_ item: CatalogItem) {
        catalogSearchFocused = false
        pages.append(Page(destination: .item(item)))
    }

    private func goBack() {
        if !pages.isEmpty { pages.removeLast() }
    }

    private var detailsBackButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel(text("Back", "Назад"))
        .help(text("Back", "Назад"))
        .accessibilityIdentifier("catalog-details-back")
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

    private var navigationControls: some View {
        HStack(spacing: 16) {
            CatalogSegmentedControl(
                title: text("Search mode", "Режим поиска"),
                selection: $showsTorrentSearch,
                options: [(false, text("Catalog", "Каталог")), (true, text("Torrent Search", "Поиск раздач"))]
            )
            .fixedSize()

            if !showsTorrentSearch, pages.isEmpty, catalogQuery.isEmpty {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 18)
                    .accessibilityHidden(true)
                categories
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var categories: some View {
        CatalogSegmentedControl(
            title: text("Category", "Раздел"),
            selection: $section,
            options: [
                (.home, text("Home", "Главная")), (.movies, text("Movies", "Фильмы")),
                (.series, text("TV Shows", "Сериалы")), (.genres, text("Genres", "Жанры"))
            ]
        )
        .fixedSize()
    }

    private enum Section { case home, movies, series, genres }

    @ViewBuilder
    private var category: some View {
        switch section {
        case .home:
            CatalogHomeView(
                repository: repository, connection: connection, text: text, revision: mainModel.catalogRefreshRevision,
                openCollection: { collection in
                    catalogSearchFocused = false
                    pages.append(Page(destination: .collection(collection)))
                },
                openItem: openItem
            )
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
            repository: repository, text: text, openItem: openItem
        )
    }

    private func destinationHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Label(text("Back", "Назад"), systemImage: "chevron.left")
            }
            Text(title).font(.headline).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct CatalogPageVisibility: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
    }
}

import SwiftUI


struct ApplicationRootView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @ObservedObject var searchModel: SearchViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selection: Binding<AppSection?> {
        Binding(
            get: { mainModel.selectedSection },
            set: { section in
                guard let section, section != mainModel.selectedSection else { return }
                mainModel.selectedSection = section
                mainModel.onSectionChanged?(section)
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebarView(
                mainModel: mainModel,
                libraryModel: libraryModel,
                selection: selection
            )
            .navigationSplitViewColumnWidth(260)
        } detail: {
            NavigationStack {
                detailContent
                    .navigationTitle(mainModel.selectedSection.title(language: mainModel.language))
                    .toolbar {
                        toolbarContent
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $libraryModel.showsPlayerSetup) {
            PlayerSetupView(
                model: libraryModel,
                language: mainModel.language
            )
        }
        .onChange(of: mainModel.jackettEnabled) { _, enabled in
            if !enabled, mainModel.selectedSection == .search {
                mainModel.selectedSection = .library
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch mainModel.selectedSection {
        case .library:
            LibraryView(
                mainModel: mainModel,
                model: libraryModel
            )
            .padding(16)
        case .search:
            SearchView(
                mainModel: mainModel,
                model: searchModel
            )
            .padding(16)
        case .server:
            MainWindowView(model: mainModel)
                .padding(16)
        case .settings:
            SettingsView(model: mainModel)
                .padding(.horizontal, 18)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch mainModel.selectedSection {
        case .library:
            ToolbarItemGroup {
                Button {
                    libraryModel.chooseTorrentFiles(language: mainModel.language)
                } label: {
                    Label(
                        mainModel.language == .russian ? "Добавить torrent-файл" : "Add torrent file",
                        systemImage: "doc.badge.plus"
                    )
                }
                .disabled(libraryModel.isAdding || !mainModel.canStop)
                .help(mainModel.language == .russian ? "Добавить torrent-файл" : "Add torrent file")

                Button {
                    libraryModel.showsMagnetSheet = true
                } label: {
                    Label(
                        mainModel.language == .russian ? "Добавить magnet-ссылку" : "Add magnet link",
                        systemImage: "link.badge.plus"
                    )
                }
                .disabled(libraryModel.isAdding || !mainModel.canStop)
                .help(mainModel.language == .russian ? "Добавить magnet-ссылку" : "Add magnet link")

                Picker("", selection: $libraryModel.displayMode) {
                    ForEach(LibraryDisplayMode.allCases) { mode in
                        Label(
                            mode.title(language: mainModel.language),
                            systemImage: mode.systemImage
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: libraryModel.displayMode) { _, mode in
                    libraryModel.setDisplayMode(mode)
                }
                .help(mainModel.language == .russian ? "Переключить вид библиотеки" : "Change library view")

                Button {
                    libraryModel.refresh()
                } label: {
                    Label(
                        mainModel.language == .russian ? "Обновить" : "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(libraryModel.isRefreshing || !mainModel.canStop)
            }

        case .search:
            ToolbarItemGroup {
                Button {
                    searchModel.search(language: mainModel.language)
                } label: {
                    Label(
                        mainModel.language == .russian ? "Искать" : "Search",
                        systemImage: "magnifyingglass"
                    )
                }
                .disabled(
                    searchModel.isSearching
                        || searchModel.query.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )

                Button {
                    searchModel.showsSettings = true
                } label: {
                    Label("Jackett", systemImage: "gearshape.2")
                }
            }

        case .server:
            ToolbarItemGroup {
                Button {
                    mainModel.onRefreshStorage?()
                } label: {
                    Label(
                        mainModel.language == .russian ? "Обновить" : "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(mainModel.isRefreshingStorage)

                Button {
                    mainModel.onOpenWeb?()
                } label: {
                    Label("Web UI", systemImage: "safari")
                }
                .disabled(!mainModel.canOpenWeb)
                .help(mainModel.language == .russian ? "Открыть Web UI" : "Open Web UI")
            }

        case .settings:
            ToolbarItemGroup {
                Button {
                    mainModel.onDownload?()
                } label: {
                    Label(
                        mainModel.language == .russian ? "Скачать TorrServer" : "Download TorrServer",
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(!mainModel.canDownload)
            }
        }
    }
}

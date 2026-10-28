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
            .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
        } detail: {
            VStack(spacing: 0) {
                SettingsPageHeader(
                    title: mainModel.selectedSection.title(language: mainModel.language),
                    message: mainModel.selectedSection.message(language: mainModel.language)
                )
                .zIndex(1)

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if columnVisibility != .detailOnly {
                            SettingsVisualStyle.sidebarDivider
                                .ignoresSafeArea(.container, edges: .vertical)
                                .transition(.identity)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .environment(
                \.settingsSidebarIsVisible,
                columnVisibility != .detailOnly
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 560)
        .background(SettingsVisualStyle.windowBackground)
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
        .onChange(of: mainModel.selectedSection) { _, section in
            mainModel.onSectionChanged?(section)
        }
        .onChange(of: mainModel.showsOfflineSection) { _, visible in
            if !visible, mainModel.selectedSection == .offline {
                mainModel.selectedSection = .library
            }
        }
        .onAppear {
            mainModel.onSectionChanged?(mainModel.selectedSection)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch mainModel.selectedSection {
        case .library:
            LibraryView(
                mainModel: mainModel,
                model: libraryModel,
                offlineDownloadManager: libraryModel.offlineDownloadManager
            )
        case .search:
            SearchView(
                mainModel: mainModel,
                model: searchModel
            )
        case .offline:
            OfflineDownloadsView(
                manager: libraryModel.offlineDownloadManager,
                preview: mainModel.offlineDownloadsPreview,
                catalog: libraryModel.offlineMediaCatalog,
                language: mainModel.language,
                openLibrary: { mainModel.selectedSection = .library },
                play: { try libraryModel.playOfflineFile($0) }
            )
        }
    }

}

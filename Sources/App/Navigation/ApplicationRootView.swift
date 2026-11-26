import SwiftUI


struct ApplicationRootView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @ObservedObject var searchModel: SearchViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hasOpenedCatalog = false

    private var catalogIsActive: Bool { mainModel.selectedSection == .search }

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
                if !catalogIsActive {
                    SettingsPageHeader(
                        title: mainModel.selectedSection.title(language: mainModel.language),
                        message: mainModel.selectedSection.message(language: mainModel.language)
                    )
                    .zIndex(1)
                }

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
        .onChange(of: mainModel.selectedSection, initial: true) { _, section in
            if section == .search { hasOpenedCatalog = true }
            mainModel.onSectionChanged?(section)
        }
        .onChange(of: mainModel.showsOfflineSection) { _, visible in
            if !visible, mainModel.selectedSection == .offline {
                mainModel.selectedSection = .library
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            if hasOpenedCatalog || catalogIsActive {
                CatalogView(mainModel: mainModel, searchModel: searchModel, libraryModel: libraryModel)
                    .opacity(catalogIsActive ? 1 : 0)
                    .allowsHitTesting(catalogIsActive)
                    .disabled(!catalogIsActive)
                    .accessibilityHidden(!catalogIsActive)
            }

            switch mainModel.selectedSection {
            case .library:
                LibraryView(
                    mainModel: mainModel,
                    model: libraryModel,
                    offlineDownloadManager: libraryModel.offlineDownloadManager
                )
            case .search:
                EmptyView()
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

}

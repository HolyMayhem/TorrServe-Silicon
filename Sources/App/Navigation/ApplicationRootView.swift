import SwiftUI


struct ApplicationRootView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @ObservedObject var searchModel: SearchViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let mainContentInset: CGFloat = 15

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
            .frame(width: 210)
            .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
        } detail: {
            detailContent
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
        .onChange(of: mainModel.selectedSection) { _, section in
            mainModel.onSectionChanged?(section)
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
                model: libraryModel
            )
            .padding(mainContentInset)
            .ignoresSafeArea(.container, edges: .top)
        case .search:
            SearchView(
                mainModel: mainModel,
                model: searchModel
            )
            .padding(mainContentInset)
            .ignoresSafeArea(.container, edges: .top)
        case .server:
            MainWindowView(model: mainModel)
        case .settings:
            SettingsView(model: mainModel)
        }
    }

}

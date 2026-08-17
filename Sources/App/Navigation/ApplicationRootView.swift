import SwiftUI


struct ApplicationRootView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @ObservedObject var searchModel: SearchViewModel

    @State private var isSidebarCompact = false

    private let mainContentInset: CGFloat = 15
    private let expandedSidebarWidth: CGFloat = 210
    private let compactSidebarWidth: CGFloat = 121

    private var sidebarWidth: CGFloat {
        isSidebarCompact ? compactSidebarWidth : expandedSidebarWidth
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { .all },
            set: { requestedVisibility in
                guard requestedVisibility == .detailOnly else { return }
                withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                    isSidebarCompact.toggle()
                }
            }
        )
    }

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
        NavigationSplitView(columnVisibility: columnVisibility) {
            AppSidebarView(
                mainModel: mainModel,
                libraryModel: libraryModel,
                selection: selection,
                isCompact: isSidebarCompact
            )
            .frame(width: sidebarWidth)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth,
                ideal: sidebarWidth,
                max: sidebarWidth
            )
        } detail: {
            detailContent
        }
        .background {
            SidebarToolbarPositioner(horizontalOffset: isSidebarCompact ? -10 : 0)
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: sidebarWidth)
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

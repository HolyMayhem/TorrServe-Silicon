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
        HStack(spacing: 0) {
            AppSidebarView(
                mainModel: mainModel,
                libraryModel: libraryModel,
                selection: selection,
                isCompact: isSidebarCompact
            )
            .frame(width: sidebarWidth)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)
                .offset(x: sidebarWidth - 0.5)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            sidebarModeButton
                .offset(x: sidebarWidth - 42, y: -30)
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

    private var sidebarModeButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                isSidebarCompact.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mainModel.language == .russian
            ? (isSidebarCompact ? "Развернуть боковую панель" : "Свернуть боковую панель")
            : (isSidebarCompact ? "Expand Sidebar" : "Collapse Sidebar"))
        .accessibilityLabel(mainModel.language == .russian
            ? (isSidebarCompact ? "Развернуть боковую панель" : "Свернуть боковую панель")
            : (isSidebarCompact ? "Expand Sidebar" : "Collapse Sidebar"))
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

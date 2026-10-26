import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case server
    case interface
    case menuBar
    case updates
    case downloads
    case metadata
    case keyboard
    case developer

    var id: Self { self }

    func title(language: AppLanguage) -> String {
        switch self {
        case .general:
            return language == .russian ? "Основные" : "General"
        case .server:
            return language == .russian ? "Сервер" : "Server"
        case .interface:
            return language == .russian ? "Интерфейс и поиск" : "Interface & Search"
        case .menuBar:
            return language == .russian ? "Строка меню" : "Menu Bar"
        case .updates:
            return language == .russian ? "Обновления" : "Updates"
        case .downloads:
            return language == .russian ? "Загрузки" : "Downloads"
        case .metadata:
            return language == .russian ? "Метаданные" : "Metadata"
        case .keyboard:
            return language == .russian ? "Клавиатура" : "Keyboard"
        case .developer:
            return language == .russian ? "Разработчик" : "Developer"
        }
    }

    func pageTitle(language: AppLanguage) -> String {
        if self == .server {
            return language == .russian ? "Настройки сервера" : "Server Settings"
        }
        if self == .keyboard {
            return language == .russian ? "Сочетания клавиш" : "Keyboard Shortcuts"
        }
        return title(language: language)
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .general:
            return language == .russian
                ? "Настройте запуск приложения, уведомления и его поведение в macOS."
                : "Configure app startup, notifications, and macOS behavior."
        case .server:
            return language == .russian
                ? "Управляйте сервером, исполняемым файлом, хранилищем и приложениями для воспроизведения."
                : "Manage the server, executable, storage, and playback apps."
        case .interface:
            return language == .russian
                ? "Выберите язык приложения и настройте источники поиска торрентов."
                : "Choose the app language and configure torrent search sources."
        case .menuBar:
            return language == .russian
                ? "Настройте значок, скорость и содержимое меню TorrServe."
                : "Configure the TorrServe menu icon, speed, and content."
        case .updates:
            return language == .russian
                ? "Обновления приложения и движка TorrServer MatriX в одном месте."
                : "Updates for the application and the TorrServer MatriX engine."
        case .downloads:
            return language == .russian
                ? "Выберите папку для сохранения офлайн-загрузок."
                : "Choose where offline downloads are stored."
        case .metadata:
            return language == .russian
                ? "Выберите источники постеров и описаний и настройте ключи API."
                : "Choose poster and description providers and configure API keys."
        case .keyboard:
            return language == .russian
                ? "Быстрые действия для медиатеки, поиска и навигации."
                : "Quick actions for your library, search, and navigation."
        case .developer:
            return language == .russian
                ? "Проверка системных уведомлений без изменения состояния сервера."
                : "Test system notifications without changing the server state."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .server: return "network"
        case .interface: return "slider.horizontal.3"
        case .menuBar: return "menubar.rectangle"
        case .updates: return "arrow.triangle.2.circlepath"
        case .downloads: return "arrow.down.circle.fill"
        case .metadata: return "film.stack.fill"
        case .keyboard: return "keyboard"
        case .developer: return "hammer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .server: return .green
        case .interface: return .purple
        case .menuBar: return .blue
        case .updates: return .orange
        case .downloads: return .cyan
        case .metadata: return .indigo
        case .keyboard: return .gray
        case .developer: return .orange
        }
    }
}

@MainActor
final class SettingsWindowNavigationModel: ObservableObject {
    @Published var selectedCategory: SettingsCategory? = .general
}

struct SettingsWindowView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var offlineDownloadManager: OfflineDownloadManager
    @ObservedObject var navigation: SettingsWindowNavigationModel
    @State private var searchText = ""
    @State private var searchEntries: [SettingsSearchEntry] = []
    @State private var searchRequest: SettingsSearchRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [SettingsSearchEntry] {
        SettingsSearchIndex.results(
            for: searchText,
            in: searchEntries.filter { entry in
                visibleCategories.contains { $0.rawValue == entry.category }
            }
        )
    }

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0 != .developer || model.developerMenuEnabled }
    }

    private var selectedCategory: SettingsCategory {
        let category = navigation.selectedCategory ?? .general
        return visibleCategories.contains(category) ? category : .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ZStack {
                SettingsVisualStyle.sidebarBackground
                    .ignoresSafeArea()

                sidebarContent
                    .searchable(
                        text: $searchText,
                        placement: .sidebar,
                        prompt: model.language == .russian ? "Поиск настроек" : "Search settings"
                    )
                    .onSubmit(of: .search) {
                        if let first = searchResults.first { openSearchResult(first) }
                    }
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 195, max: 210)
        } detail: {
            VStack(spacing: 0) {
                SettingsPageHeader(
                    title: selectedCategory.pageTitle(language: model.language),
                    message: selectedCategory.message(language: model.language),
                    isSettingsPage: true
                )
                .zIndex(1)

                Group {
                    if selectedCategory == .server {
                        MainWindowView(model: model)
                    } else {
                        SettingsView(
                            model: model,
                            offlineDownloadManager: offlineDownloadManager,
                            category: selectedCategory
                        )
                    }
                }
                .id(selectedCategory)
                .environment(\.settingsSearchCategory, selectedCategory)
                .environment(\.settingsSearchRequest, searchRequest)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .environment(
                \.settingsSidebarIsVisible,
                columnVisibility != .detailOnly
            )
        }
        .overlay(alignment: .topLeading) {
            if isSearching { searchIndexContent }
        }
        .onChange(of: searchText) { _, _ in
            searchRequest = nil
            if !isSearching { searchEntries = [] }
        }
        .onChange(of: model.language) { _, _ in
            searchRequest = nil
        }
        .onChange(of: model.developerMenuEnabled) { _, enabled in
            searchRequest = nil
            searchEntries = []
            if !enabled, navigation.selectedCategory == .developer {
                navigation.selectedCategory = .general
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 540)
        .background(SettingsVisualStyle.windowBackground)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if isSearching {
            List {
                if searchResults.isEmpty {
                    Text(model.language == .russian ? "Ничего не найдено" : "No results")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(searchResults) { entry in
                    Button {
                        openSearchResult(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(searchResultLocation(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .background {
                            if searchRequest?.entry.id == entry.id {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.12))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(searchRequest?.entry.id == entry.id ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
        } else {
            List(visibleCategories, selection: $navigation.selectedCategory) { category in
                SettingsCategoryRow(category: category, language: model.language)
                    .tag(category)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
        }
    }

    /// Evaluate the actual page builders while searching. Searchable rows emit only
    /// titles in this mode: editors/actions and page lifecycle hooks never mount.
    private var searchIndexContent: some View {
        VStack {
            ForEach(visibleCategories) { category in
                Group {
                    if category == .server {
                        MainWindowView(model: model, isSearchIndex: true)
                    } else {
                        SettingsView(
                            model: model,
                            offlineDownloadManager: offlineDownloadManager,
                            category: category,
                            isSearchIndex: true
                        )
                    }
                }
                .environment(\.settingsSearchCategory, category)
            }
        }
        .environment(\.isIndexingSettings, true)
        .disabled(true)
        .onPreferenceChange(SettingsSearchEntriesKey.self) { searchEntries = $0 }
        .frame(width: SettingsScreenLayout.contentMaxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .frame(width: 0, height: 0)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func searchResultLocation(_ entry: SettingsSearchEntry) -> String {
        guard let category = SettingsCategory(rawValue: entry.category) else { return entry.group }
        let title = category.title(language: model.language)
        return entry.group.isEmpty ? title : "\(title) › \(entry.group)"
    }

    private func openSearchResult(_ entry: SettingsSearchEntry) {
        guard let category = SettingsCategory(rawValue: entry.category), visibleCategories.contains(category) else { return }
        navigation.selectedCategory = category
        searchRequest = SettingsSearchRequest(entry: entry)
    }

}

private struct SettingsCategoryRow: View {
    let category: SettingsCategory
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(category.tint.gradient)

                Image(systemName: category.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            Text(category.title(language: language))
                .font(.callout)
                .lineLimit(1)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

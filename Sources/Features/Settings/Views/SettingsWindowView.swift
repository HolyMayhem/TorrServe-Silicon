import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case server
    case interface
    case menuBar
    case updates
    case downloads
    case metadata

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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var filteredCategories: [SettingsCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter {
            $0.title(language: model.language).localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCategory: SettingsCategory {
        navigation.selectedCategory ?? .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ZStack {
                SettingsVisualStyle.sidebarBackground
                    .ignoresSafeArea()

                List(filteredCategories, selection: $navigation.selectedCategory) { category in
                    SettingsCategoryRow(category: category, language: model.language)
                        .tag(category)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)
                .searchable(
                    text: $searchText,
                    placement: .sidebar,
                    prompt: model.language == .russian ? "Поиск" : "Search"
                )
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 195, max: 210)
        } detail: {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsVisualStyle.windowBackground)
            .environment(
                \.settingsSidebarIsVisible,
                columnVisibility != .detailOnly
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 540)
        .background(SettingsVisualStyle.windowBackground)
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

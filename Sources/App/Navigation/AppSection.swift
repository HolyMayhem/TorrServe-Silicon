import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case search
    case server
    case settings

    var id: Self { self }

    func title(language: AppLanguage) -> String {
        switch self {
        case .library:
            return language == .russian ? "Библиотека" : "Library"
        case .search:
            return language == .russian ? "Поиск" : "Search"
        case .server:
            return language == .russian ? "Сервер" : "Server"
        case .settings:
            return language == .russian ? "Настройки" : "Settings"
        }
    }

    func sidebarTitle(language: AppLanguage) -> String {
        switch self {
        case .library, .search:
            return title(language: language)
        case .server:
            return language == .russian ? "Настройки сервера" : "Server Settings"
        case .settings:
            return language == .russian ? "Общие настройки" : "General Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "film.stack"
        case .search: return "magnifyingglass"
        case .server: return "network"
        case .settings: return "gearshape"
        }
    }
}

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case search

    var id: Self { self }

    func title(language: AppLanguage) -> String {
        switch self {
        case .library:
            return language == .russian ? "Библиотека" : "Library"
        case .search:
            return language == .russian ? "Поиск" : "Search"
        }
    }

    func sidebarTitle(language: AppLanguage) -> String {
        switch self {
        case .library, .search:
            return title(language: language)
        }
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .library:
            return language == .russian
                ? "Управляйте библиотекой, воспроизведением и офлайн-загрузками."
                : "Manage your library, playback, and offline downloads."
        case .search:
            return language == .russian
                ? "Находите фильмы и сериалы через Jackett и добавляйте их в библиотеку."
                : "Find movies and series through Jackett and add them to your library."
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "film.stack"
        case .search: return "magnifyingglass"
        }
    }
}

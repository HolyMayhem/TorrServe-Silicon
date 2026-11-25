import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case search
    case offline

    var id: Self { self }

    func title(language: AppLanguage) -> String {
        switch self {
        case .library:
            return language == .russian ? "Библиотека" : "Library"
        case .search:
            return language == .russian ? "Каталог" : "Catalog"
        case .offline:
            return language == .russian ? "Офлайн" : "Offline"
        }
    }

    func sidebarTitle(language: AppLanguage) -> String {
        switch self {
        case .library, .search, .offline:
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
                ? "Фильмы, сериалы и поиск раздач."
                : "Browse movies and TV shows and find torrents."
        case .offline:
            return language == .russian
                ? "Сохранённые фильмы и серии для просмотра без интернета."
                : "Saved movies and episodes to watch without an internet connection."
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "film.stack"
        case .search: return "house"
        case .offline: return "arrow.down.circle"
        }
    }
}

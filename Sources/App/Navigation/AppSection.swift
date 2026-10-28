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
            return language == .russian ? "Поиск" : "Search"
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
                ? "Находите раздачи через TorrentSearch и Jackett и добавляйте их в библиотеку."
                : "Search TorrentSearch and Jackett and add releases to your library."
        case .offline:
            return language == .russian
                ? "Сохранённые фильмы и серии для просмотра без интернета."
                : "Saved movies and episodes to watch without an internet connection."
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "film.stack"
        case .search: return "magnifyingglass"
        case .offline: return "arrow.down.circle"
        }
    }
}

import AppKit

/// Shared by the native menu and the Settings reference so their labels and keys agree.
enum AppKeyboardShortcut: String, CaseIterable, Identifiable {
    case addTorrent, addMagnet, focusSearch, refresh, library, search
    case selectAll, deselectAll, copyStream, pasteMagnet, play, remove, previous, next, escape
    case list, posters, cards, settings, shortcuts

    var id: Self { self }

    enum Group: CaseIterable {
        case navigation, media, appearance
        func title(language: AppLanguage) -> String {
            switch self {
            case .navigation: return language == .russian ? "Приложение и навигация" : "App & Navigation"
            case .media: return language == .russian ? "Медиатека" : "Library"
            case .appearance: return language == .russian ? "Вид медиатеки" : "Library View"
            }
        }
    }

    var group: Group {
        switch self {
        case .addTorrent, .addMagnet, .selectAll, .deselectAll, .copyStream, .pasteMagnet, .play, .remove, .previous, .next, .escape: return .media
        case .list, .posters, .cards: return .appearance
        default: return .navigation
        }
    }

    var keyEquivalent: String {
        switch self {
        case .addTorrent: return "o"
        case .addMagnet: return "l"
        case .focusSearch: return "f"
        case .refresh: return "r"
        case .library, .list: return "1"
        case .search, .posters: return "2"
        case .cards: return "3"
        case .selectAll, .deselectAll: return "a"
        case .copyStream: return "c"
        case .pasteMagnet: return "v"
        case .play: return "\r"
        case .remove: return "\u{8}"
        case .previous: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case .next: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .escape: return "\u{1b}"
        case .settings: return ","
        case .shortcuts: return "/"
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .deselectAll, .shortcuts: return [.command, .shift]
        case .list, .posters, .cards: return [.command, .option]
        case .play, .remove, .previous, .next, .escape: return []
        default: return .command
        }
    }

    var displayKeys: [String] {
        switch self {
        case .selectAll: return ["⌘A", "⌃A"]
        case .play: return ["↩"]
        case .remove: return ["⌫"]
        case .previous: return ["↑"]
        case .next: return ["↓"]
        case .escape: return ["esc"]
        default:
            let prefix = (modifiers.contains(.option) ? "⌥" : "")
                + (modifiers.contains(.shift) ? "⇧" : "")
                + (modifiers.contains(.command) ? "⌘" : "")
            return [prefix + keyEquivalent.uppercased()]
        }
    }

    func title(language: AppLanguage) -> String {
        let ru = language == .russian
        switch self {
        case .addTorrent: return ru ? "Добавить torrent-файл…" : "Add Torrent File…"
        case .addMagnet: return ru ? "Добавить magnet-ссылку…" : "Add Magnet Link…"
        case .focusSearch: return ru ? "Поиск на текущей странице" : "Search Current Page"
        case .refresh: return ru ? "Обновить текущую страницу" : "Refresh Current Page"
        case .library: return ru ? "Медиатека" : "Library"
        case .search: return ru ? "Поиск торрентов" : "Torrent Search"
        case .selectAll: return ru ? "Выделить все видимые фильмы" : "Select All Visible Items"
        case .deselectAll: return ru ? "Снять выделение" : "Deselect All"
        case .copyStream: return ru ? "Скопировать ссылку на трансляцию" : "Copy Stream URL"
        case .pasteMagnet: return ru ? "Добавить magnet-ссылку из буфера" : "Add Magnet Link from Clipboard"
        case .play: return ru ? "Смотреть выбранный фильм" : "Play Selected Item"
        case .remove: return ru ? "Удалить выбранное с подтверждением" : "Remove Selection with Confirmation"
        case .previous: return ru ? "Выбрать предыдущий фильм" : "Select Previous Item"
        case .next: return ru ? "Выбрать следующий фильм" : "Select Next Item"
        case .escape: return ru ? "Выйти из поиска или снять выделение" : "Leave Search or Clear Selection"
        case .list: return ru ? "Список" : "List"
        case .posters: return ru ? "Постеры" : "Posters"
        case .cards: return ru ? "Карточки" : "Cards"
        case .settings: return ru ? "Открыть настройки" : "Open Settings"
        case .shortcuts: return ru ? "Сочетания клавиш…" : "Keyboard Shortcuts…"
        }
    }
}

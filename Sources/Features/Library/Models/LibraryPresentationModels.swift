import Foundation

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case posters
    case cards

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .compact:
            return language == .russian ? "Список" : "List"
        case .posters:
            return language == .russian ? "Постеры" : "Posters"
        case .cards:
            return language == .russian ? "Карточки" : "Cards"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: return "sidebar.left"
        case .posters: return "square.grid.2x2"
        case .cards: return "rectangle.grid.1x2"
        }
    }
}

enum ExternalPlayerChoice: String, CaseIterable, Identifiable {
    case quickTime
    case iina
    case vlc
    case infuse
    case systemDefault
    case custom

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .quickTime:
            return "QuickTime"
        case .iina:
            return "IINA"
        case .vlc:
            return "VLC"
        case .infuse:
            return "Infuse"
        case .systemDefault:
            return language == .russian ? "По умолчанию macOS" : "macOS Default"
        case .custom:
            return language == .russian ? "Другое приложение…" : "Other app…"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .quickTime: return "com.apple.QuickTimePlayerX"
        case .iina: return "com.colliderli.iina"
        case .vlc: return "org.videolan.vlc"
        case .infuse: return "com.firecore.infuse"
        case .systemDefault, .custom: return nil
        }
    }

    var downloadURL: URL? {
        switch self {
        case .iina:
            return URL(string: "https://iina.io/download/")
        case .vlc:
            return URL(string: "https://www.videolan.org/vlc/download-macosx.html")
        case .infuse:
            return URL(string: "https://apps.apple.com/app/infuse/id1136220934")
        default:
            return nil
        }
    }
}

struct DetectedPlayer: Identifiable, Equatable {
    let choice: ExternalPlayerChoice
    let applicationURL: URL?

    var id: String { choice.id }
    var isInstalled: Bool { applicationURL != nil }
}

struct LibraryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

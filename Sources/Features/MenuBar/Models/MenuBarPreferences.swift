import Foundation

enum MenuBarPopoverSection: String, CaseIterable, Identifiable {
    case serverVersion
    case serverAddress
    case recentMaterial
    case activeTorrents
    case cache
    case speed
    case quickActions
    case restart
    case qrCode
    case settings

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .serverVersion:
            return language == .russian ? "MatriX и обновления" : "MatriX & updates"
        case .serverAddress:
            return language == .russian ? "Адрес сервера" : "Server address"
        case .activeTorrents:
            return language == .russian ? "Активные торренты" : "Active torrents"
        case .cache:
            return language == .russian ? "Занятость кэша" : "Cache usage"
        case .restart:
            return language == .russian ? "Перезапуск сервера" : "Restart server"
        case .settings:
            return language == .russian ? "Настройки" : "Settings"
        case .recentMaterial:
            return language == .russian ? "Последний материал" : "Latest material"
        case .speed:
            return language == .russian ? "Скорость" : "Speed"
        case .quickActions:
            return language == .russian ? "Быстрые действия" : "Quick actions"
        case .qrCode:
            return language == .russian ? "QR-код" : "QR code"
        }
    }

    var systemImage: String {
        switch self {
        case .serverVersion: return "shippingbox"
        case .serverAddress: return "network"
        case .activeTorrents: return "square.stack.3d.up"
        case .cache: return "memorychip"
        case .restart: return "arrow.clockwise"
        case .settings: return "gearshape"
        case .recentMaterial: return "film.stack"
        case .speed: return "chart.xyaxis.line"
        case .quickActions: return "rectangle.3.group"
        case .qrCode: return "qrcode"
        }
    }
}

struct MenuBarPreferences: Equatable {
    var isIconVisible = true
    var showsSpeed = true
    var showsRecentMaterial = true
    var showsQuickActions = true
    var showsQRCode = true
    var expandsQRCodeOnOpen = false
    var showsServerAddress = false
    var showsCopyAddress = false
    var showsServerVersion = false
    var showsUpdateStatus = false
    var showsRestart = false
    var showsCache = false
    var showsActiveTorrents = false
    var showsSettings = false
    var sectionOrder = MenuBarPopoverSection.allCases

    static let defaults = MenuBarPreferences()

    func isVisible(_ section: MenuBarPopoverSection) -> Bool {
        switch section {
        case .serverAddress: return showsServerAddress || showsCopyAddress
        case .serverVersion: return showsServerVersion || showsUpdateStatus
        case .restart: return showsRestart
        case .cache: return showsCache
        case .activeTorrents: return showsActiveTorrents
        case .settings: return showsSettings
        case .recentMaterial: return showsRecentMaterial
        case .speed: return showsSpeed
        case .quickActions: return showsQuickActions
        case .qrCode: return showsQRCode
        }
    }

    static func normalizedOrder(
        _ sections: [MenuBarPopoverSection]
    ) -> [MenuBarPopoverSection] {
        var seen: Set<MenuBarPopoverSection> = []
        var result = sections.filter { seen.insert($0).inserted }
        result.append(contentsOf: MenuBarPopoverSection.allCases.filter {
            seen.insert($0).inserted
        })
        return result
    }
}

final class MenuBarPreferencesStore {
    enum Key {
        static let iconVisible = "MenuBarIconVisible"
        static let speed = "ShowSpeedInMenuBar"
        static let recentMaterial = "MenuBarShowRecentMaterial"
        static let quickActions = "MenuBarShowQuickActions"
        static let qrCode = "MenuBarShowQRCode"
        static let expandQRCode = "MenuBarExpandQRCodeOnOpen"
        static let serverAddress = "MenuBarShowServerAddress"
        static let copyAddress = "MenuBarShowCopyAddress"
        static let serverVersion = "MenuBarShowServerVersion"
        static let updateStatus = "MenuBarShowUpdateStatus"
        static let restart = "MenuBarShowRestart"
        static let cache = "MenuBarShowCache"
        static let activeTorrents = "MenuBarShowActiveTorrents"
        static let settings = "MenuBarShowSettings"
        static let sectionOrder = "MenuBarPopoverSectionOrder"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MenuBarPreferences {
        let rawOrder = defaults.stringArray(forKey: Key.sectionOrder) ?? []
        let savedOrder = rawOrder.compactMap(MenuBarPopoverSection.init(rawValue:))
        return MenuBarPreferences(
            isIconVisible: bool(forKey: Key.iconVisible, fallback: true),
            showsSpeed: bool(forKey: Key.speed, fallback: true),
            showsRecentMaterial: bool(forKey: Key.recentMaterial, fallback: true),
            showsQuickActions: bool(forKey: Key.quickActions, fallback: true),
            showsQRCode: bool(forKey: Key.qrCode, fallback: true),
            expandsQRCodeOnOpen: bool(forKey: Key.expandQRCode, fallback: false),
            showsServerAddress: bool(forKey: Key.serverAddress, fallback: false),
            showsCopyAddress: bool(forKey: Key.copyAddress, fallback: false),
            showsServerVersion: bool(forKey: Key.serverVersion, fallback: false),
            showsUpdateStatus: bool(forKey: Key.updateStatus, fallback: false),
            showsRestart: bool(forKey: Key.restart, fallback: false),
            showsCache: bool(forKey: Key.cache, fallback: false),
            showsActiveTorrents: bool(forKey: Key.activeTorrents, fallback: false),
            showsSettings: bool(forKey: Key.settings, fallback: false),
            sectionOrder: MenuBarPreferences.normalizedOrder(savedOrder)
        )
    }

    func save(_ preferences: MenuBarPreferences) {
        let normalizedOrder = MenuBarPreferences.normalizedOrder(
            preferences.sectionOrder
        )
        defaults.set(preferences.isIconVisible, forKey: Key.iconVisible)
        defaults.set(preferences.showsSpeed, forKey: Key.speed)
        defaults.set(preferences.showsRecentMaterial, forKey: Key.recentMaterial)
        defaults.set(preferences.showsQuickActions, forKey: Key.quickActions)
        defaults.set(preferences.showsQRCode, forKey: Key.qrCode)
        defaults.set(preferences.expandsQRCodeOnOpen, forKey: Key.expandQRCode)
        defaults.set(preferences.showsServerAddress, forKey: Key.serverAddress)
        defaults.set(preferences.showsCopyAddress, forKey: Key.copyAddress)
        defaults.set(preferences.showsServerVersion, forKey: Key.serverVersion)
        defaults.set(preferences.showsUpdateStatus, forKey: Key.updateStatus)
        defaults.set(preferences.showsRestart, forKey: Key.restart)
        defaults.set(preferences.showsCache, forKey: Key.cache)
        defaults.set(preferences.showsActiveTorrents, forKey: Key.activeTorrents)
        defaults.set(preferences.showsSettings, forKey: Key.settings)
        defaults.set(normalizedOrder.map(\.rawValue), forKey: Key.sectionOrder)
    }

    private func bool(forKey key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}

/// Shared descriptors keep the editor and its search index in sync.
enum MenuBarExtraOption: String, CaseIterable, Identifiable {
    case serverAddress
    case copyAddress
    case serverVersion
    case updateStatus
    case restart
    case cache
    case activeTorrents
    case settings

    var id: Self { self }

    var keyPath: WritableKeyPath<MenuBarPreferences, Bool> {
        switch self {
        case .serverAddress: return \.showsServerAddress
        case .copyAddress: return \.showsCopyAddress
        case .serverVersion: return \.showsServerVersion
        case .updateStatus: return \.showsUpdateStatus
        case .restart: return \.showsRestart
        case .cache: return \.showsCache
        case .activeTorrents: return \.showsActiveTorrents
        case .settings: return \.showsSettings
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .serverAddress: return language == .russian ? "Адрес сервера" : "Server address"
        case .copyAddress: return language == .russian ? "Кнопка копирования адреса" : "Copy address button"
        case .serverVersion: return language == .russian ? "Версия MatriX" : "MatriX version"
        case .updateStatus: return language == .russian ? "Наличие обновления MatriX" : "MatriX update status"
        case .restart: return language == .russian ? "Кнопка перезапуска сервера" : "Restart server button"
        case .cache: return language == .russian ? "Занятость кэша" : "Cache usage"
        case .activeTorrents: return language == .russian ? "Количество активных торрентов" : "Active torrent count"
        case .settings: return language == .russian ? "Кнопка настроек" : "Settings button"
        }
    }
}

enum MenuBarSectionOrdering {
    static func moving(
        _ sections: [MenuBarPopoverSection],
        section: MenuBarPopoverSection,
        to destinationIndex: Int
    ) -> [MenuBarPopoverSection] {
        guard let sourceIndex = sections.firstIndex(of: section) else {
            return MenuBarPreferences.normalizedOrder(sections)
        }

        var result = sections
        result.remove(at: sourceIndex)
        let insertionIndex = min(max(destinationIndex, 0), result.endIndex)
        result.insert(section, at: insertionIndex)
        return MenuBarPreferences.normalizedOrder(result)
    }
}

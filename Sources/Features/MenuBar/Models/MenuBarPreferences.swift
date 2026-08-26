import Foundation

enum MenuBarPopoverSection: String, CaseIterable, Identifiable {
    case recentMaterial
    case speed
    case quickActions
    case qrCode

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
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
    var sectionOrder = MenuBarPopoverSection.allCases

    static let defaults = MenuBarPreferences()

    func isVisible(_ section: MenuBarPopoverSection) -> Bool {
        switch section {
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
        defaults.set(normalizedOrder.map(\.rawValue), forKey: Key.sectionOrder)
    }

    private func bool(forKey key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}

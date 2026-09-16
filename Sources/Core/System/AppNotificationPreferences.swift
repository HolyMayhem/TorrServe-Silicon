import Foundation

enum AppNotificationEvent: String, CaseIterable, Identifiable {
    case offlineDownloadCompleted
    case offlineDownloadFailed
    case serverStarted
    case serverStopped
    case criticalError
    case torrServerUpdated

    var id: String { rawValue }

    fileprivate var storageKey: String {
        "NotificationEvent.\(rawValue)"
    }
}

struct AppNotificationPreferences: Equatable {
    private static let playsSoundKey = "NotificationPlaysSound"

    var playsSound: Bool
    private var eventStates: [AppNotificationEvent: Bool]

    static let defaults = AppNotificationPreferences(
        playsSound: true,
        eventStates: Dictionary(
            uniqueKeysWithValues: AppNotificationEvent.allCases.map { ($0, true) }
        )
    )

    init(
        playsSound: Bool = true,
        eventStates: [AppNotificationEvent: Bool] = [:]
    ) {
        self.playsSound = playsSound
        self.eventStates = Dictionary(
            uniqueKeysWithValues: AppNotificationEvent.allCases.map { event in
                (event, eventStates[event] ?? true)
            }
        )
    }

    subscript(event: AppNotificationEvent) -> Bool {
        get { eventStates[event] ?? true }
        set { eventStates[event] = newValue }
    }

    static func registerDefaults(in userDefaults: UserDefaults = .standard) {
        var defaults: [String: Any] = [playsSoundKey: true]
        for event in AppNotificationEvent.allCases {
            defaults[event.storageKey] = true
        }
        userDefaults.register(defaults: defaults)
    }

    static func load(from userDefaults: UserDefaults = .standard) -> Self {
        var eventStates: [AppNotificationEvent: Bool] = [:]
        for event in AppNotificationEvent.allCases {
            eventStates[event] = userDefaults.bool(forKey: event.storageKey)
        }
        return AppNotificationPreferences(
            playsSound: userDefaults.bool(forKey: playsSoundKey),
            eventStates: eventStates
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(playsSound, forKey: Self.playsSoundKey)
        for event in AppNotificationEvent.allCases {
            userDefaults.set(self[event], forKey: event.storageKey)
        }
    }
}

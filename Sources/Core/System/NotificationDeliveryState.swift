import Foundation

enum NotificationAuthorizationState: Equatable {
    case unknown, notDetermined, authorized, provisional, denied, legacyUnknown
}

struct NotificationSystemState: Equatable {
    var authorization: NotificationAuthorizationState = .unknown
    var bannersEnabled: Bool? = nil
    var soundsEnabled: Bool? = nil
    var authorizationError: String? = nil

    func message(isRussian: Bool) -> String {
        if let authorizationError { return authorizationError }
        switch authorization {
        case .unknown:
            return isRussian ? "Проверка разрешения macOS…" : "Checking macOS authorization…"
        case .notDetermined:
            return isRussian ? "Разрешение macOS ещё не запрошено." : "macOS authorization has not been requested."
        case .denied:
            return isRussian ? "macOS запрещает уведомления. Разрешите их в системных настройках." : "Notifications are blocked by macOS. Allow them in System Settings."
        case .legacyUnknown:
            return isRussian
                ? "Для этой сборки системное разрешение нельзя проверить через API. Проверьте его в настройках уведомлений macOS."
                : "This build cannot read system authorization through the API. Check macOS notification settings."
        case .provisional:
            return isRussian ? "Разрешена тихая доставка. Баннер может не появиться." : "Quiet delivery is allowed. A banner may not appear."
        case .authorized:
            if bannersEnabled == false {
                return isRussian ? "Разрешено, но показ предупреждений выключен в macOS." : "Authorized, but alerts are disabled in macOS."
            }
            return isRussian ? "Уведомления разрешены в macOS." : "Notifications are authorized in macOS."
        }
    }
}

enum NotificationDeliveryResult: Equatable {
    case accepted
    case legacyDelivered
    case legacyUnconfirmed
    case appDisabled
    case eventDisabled
    case systemBlocked
    case authorizationRequired
    case failed(String)

    var isFailure: Bool {
        switch self {
        case .accepted, .legacyDelivered: return false
        default: return true
        }
    }

    func message(isRussian: Bool) -> String {
        switch self {
        case .accepted:
            return isRussian ? "macOS приняла уведомление. Показ баннера зависит от системных настроек и фокусирования." : "macOS accepted the notification. Banner presentation depends on system settings and Focus."
        case .legacyDelivered:
            return isRussian ? "Центр уведомлений подтвердил доставку. Показ баннера зависит от настроек macOS." : "Notification Center acknowledged delivery. Banner presentation depends on macOS settings."
        case .legacyUnconfirmed:
            return isRussian ? "Запрос отправлен, но подтверждения доставки нет. Проверьте разрешение в macOS." : "Submitted without delivery confirmation. Check macOS authorization."
        case .appDisabled:
            return isRussian ? "Не отправлено: уведомления приложения выключены." : "Not sent: app notifications are disabled."
        case .eventDisabled:
            return isRussian ? "Не отправлено: этот тип события выключен." : "Not sent: this event type is disabled."
        case .systemBlocked:
            return isRussian ? "Не отправлено: macOS запрещает уведомления." : "Not sent: notifications are blocked by macOS."
        case .authorizationRequired:
            return isRussian ? "Не отправлено: требуется разрешение macOS." : "Not sent: macOS authorization is required."
        case .failed(let message):
            return isRussian ? "Ошибка отправки: \(message)" : "Delivery error: \(message)"
        }
    }
}

enum NotificationDeliveryPolicy {
    static func blockedResult(enabled: Bool, eventEnabled: Bool, authorization: NotificationAuthorizationState) -> NotificationDeliveryResult? {
        guard enabled else { return .appDisabled }
        guard eventEnabled else { return .eventDisabled }
        switch authorization {
        case .denied: return .systemBlocked
        case .notDetermined, .unknown: return .authorizationRequired
        case .authorized, .provisional, .legacyUnknown: return nil
        }
    }
}

extension AppNotificationEvent {
    func displayTitle(isRussian: Bool) -> String {
        switch self {
        case .offlineDownloadCompleted: return isRussian ? "Загрузка завершена" : "Download completed"
        case .offlineDownloadFailed: return isRussian ? "Ошибка загрузки" : "Download failed"
        case .serverStarted: return isRussian ? "Сервер запущен" : "Server started"
        case .serverStopped: return isRussian ? "Сервер остановлен" : "Server stopped"
        case .criticalError: return isRussian ? "Критическая ошибка" : "Critical error"
        case .torrServerUpdated: return isRussian ? "TorrServer обновлён" : "TorrServer updated"
        }
    }

    func testBody(isRussian: Bool) -> String {
        switch self {
        case .offlineDownloadCompleted: return isRussian ? "Пример: Фильм.mkv успешно загружен. Это тест." : "Example: Movie.mkv finished downloading. This is a test."
        case .offlineDownloadFailed: return isRussian ? "Пример ошибки загрузки Фильм.mkv. Это тест, реальной ошибки нет." : "Example failure downloading Movie.mkv. This is a test, not a real failure."
        case .serverStarted: return isRussian ? "Проверка уведомления о запуске. Состояние сервера не меняется." : "Testing the startup notification. The server state is unchanged."
        case .serverStopped: return isRussian ? "Проверка уведомления об остановке. Сервер не останавливается." : "Testing the stop notification. The server is not stopped."
        case .criticalError: return isRussian ? "Тест критической ошибки. С приложением всё в порядке." : "Test critical error. The app is operating normally."
        case .torrServerUpdated: return isRussian ? "Проверка уведомления об обновлении. Обновление не устанавливается." : "Testing the update notification. No update is installed."
        }
    }
}

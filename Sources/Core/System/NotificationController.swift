import AppKit
import OSLog
import Security
import UserNotifications

@MainActor
final class NotificationController: NSObject,
    UNUserNotificationCenterDelegate,
    NSUserNotificationCenterDelegate
{
    private let center = UNUserNotificationCenter.current()
    private let usesLegacyDelivery: Bool
    private var authorizationRequestInFlight = false
    private var authorizationRevision = 0
    private var pendingLegacyDeliveries: [String: (NotificationDeliveryResult) -> Void] = [:]
    private let logger = Logger(subsystem: "com.holymayhem.torrserver", category: "Notifications")
    private(set) var systemState = NotificationSystemState()
    var onSystemStateChange: ((NotificationSystemState) -> Void)?
    var onDeliveryResult: ((NotificationDeliveryResult) -> Void)?

    override init() {
        usesLegacyDelivery = !Self.hasStableSigningIdentity()
        super.init()
        center.delegate = self
        if usesLegacyDelivery {
            systemState.authorization = .legacyUnknown
            NSUserNotificationCenter.default.delegate = self
        }
    }

    /// Store user intent separately from system authorization. A refresh must not
    /// silently erase this preference when the user temporarily blocks the app.
    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (_ enabled: Bool, _ shouldOpenSettings: Bool) -> Void
    ) {
        guard !authorizationRequestInFlight else { return }
        authorizationRevision += 1
        UserDefaults.standard.set(enabled, forKey: notificationsEnabledKey)
        guard enabled else {
            completion(false, false)
            return
        }
        if usesLegacyDelivery {
            publishLegacyState()
            completion(true, false)
            return
        }
        authorizationRequestInFlight = true
        Task { [weak self] in
            guard let self else { return }
            var settings = await center.notificationSettings()
            var requestError: String?
            if settings.authorizationStatus == .notDetermined {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    requestError = error.localizedDescription
                    logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .private)")
                }
                settings = await center.notificationSettings()
            }
            updateSystemState(settings, error: requestError)
            authorizationRequestInFlight = false
            completion(true, settings.authorizationStatus == .denied)
        }
    }

    func synchronizeEnabledState(completion: @escaping (Bool) -> Void) {
        if usesLegacyDelivery {
            publishLegacyState()
            completion(UserDefaults.standard.bool(forKey: notificationsEnabledKey))
            return
        }
        guard !authorizationRequestInFlight else { return }
        let revision = authorizationRevision
        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            // Ignore refreshes that predate a newer toggle/authorization request.
            guard !authorizationRequestInFlight, revision == authorizationRevision else { return }
            updateSystemState(settings)
            completion(UserDefaults.standard.bool(forKey: notificationsEnabledKey))
        }
    }

    func setPreferences(_ preferences: AppNotificationPreferences) {
        preferences.save()
    }

    func send(
        event: AppNotificationEvent,
        title: String,
        body: String,
        completion: ((NotificationDeliveryResult) -> Void)? = nil
    ) {
        // Report local suppression immediately; do not prompt for authorization
        // from a background event. The settings toggle owns that interaction.
        guard UserDefaults.standard.bool(forKey: notificationsEnabledKey) else {
            finish(.appDisabled, completion: completion)
            return
        }
        guard AppNotificationPreferences.load()[event] else {
            finish(.eventDisabled, completion: completion)
            return
        }
        if usesLegacyDelivery {
            sendLegacy(title: title, body: body, completion: completion)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let revision = authorizationRevision
            let settings = await center.notificationSettings()
            guard !authorizationRequestInFlight, revision == authorizationRevision else {
                finish(UserDefaults.standard.bool(forKey: notificationsEnabledKey)
                    ? .authorizationRequired : .appDisabled, completion: completion)
                return
            }
            updateSystemState(settings)
            let preferences = AppNotificationPreferences.load()
            if let blocked = NotificationDeliveryPolicy.blockedResult(
                enabled: UserDefaults.standard.bool(forKey: notificationsEnabledKey),
                eventEnabled: preferences[event], authorization: systemState.authorization
            ) {
                finish(blocked, completion: completion)
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = preferences.playsSound ? .default : nil
            do {
                try await center.add(UNNotificationRequest(
                    identifier: UUID().uuidString, content: content, trigger: nil
                ))
                finish(.accepted, completion: completion)
            } catch {
                logger.error("Notification submission failed: \(error.localizedDescription, privacy: .private)")
                finish(.failed(error.localizedDescription), completion: completion)
            }
        }
    }

    private func sendLegacy(
        title: String, body: String,
        completion: ((NotificationDeliveryResult) -> Void)?
    ) {
        let identifier = UUID().uuidString
        let notification = NSUserNotification()
        notification.identifier = identifier
        notification.title = title
        notification.informativeText = body
        if AppNotificationPreferences.load().playsSound {
            notification.soundName = NSUserNotificationDefaultSoundName
        }
        // deliver() returning is NOT confirmation of delivery or authorization.
        pendingLegacyDeliveries[identifier] = { [weak self] result in
            self?.finish(result, completion: completion)
        }
        NSUserNotificationCenter.default.deliver(notification)
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            guard let self, let pending = pendingLegacyDeliveries.removeValue(forKey: identifier) else { return }
            logger.warning("Legacy notification delivery was not acknowledged")
            pending(.legacyUnconfirmed)
        }
    }

    private func publishLegacyState() {
        systemState = NotificationSystemState(authorization: .legacyUnknown)
        onSystemStateChange?(systemState)
    }

    private func updateSystemState(_ settings: UNNotificationSettings, error: String? = nil) {
        let authorization: NotificationAuthorizationState
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: authorization = .authorized
        case .provisional: authorization = .provisional
        case .denied: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .unknown
        }
        systemState = NotificationSystemState(
            authorization: authorization,
            bannersEnabled: settings.alertSetting == .enabled && settings.alertStyle != .none,
            soundsEnabled: settings.soundSetting == .enabled,
            authorizationError: error
        )
        onSystemStateChange?(systemState)
    }

    private func finish(_ result: NotificationDeliveryResult, completion: ((NotificationDeliveryResult) -> Void)?) {
        onDeliveryResult?(result)
        completion?(result)
    }

    private static func hasStableSigningIdentity() -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess, let staticCode else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
            let dictionary = signingInformation as NSDictionary?
        else {
            return false
        }

        let teamIdentifierKey = kSecCodeInfoTeamIdentifier as String
        guard let teamIdentifier = dictionary[teamIdentifierKey] as? String else {
            return false
        }
        return !teamIdentifier.isEmpty
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didDeliver notification: NSUserNotification
    ) {
        guard let identifier = notification.identifier else { return }
        Task { @MainActor [weak self] in
            self?.pendingLegacyDeliveries.removeValue(forKey: identifier)?(.legacyDelivered)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}

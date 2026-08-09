import AppKit
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

    override init() {
        usesLegacyDelivery = !Self.hasStableSigningIdentity()
        super.init()
        center.delegate = self
        if usesLegacyDelivery {
            NSUserNotificationCenter.default.delegate = self
        }
    }

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (_ enabled: Bool, _ shouldOpenSettings: Bool) -> Void
    ) {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: notificationsEnabledKey)
            completion(false, false)
            return
        }

        // Ad-hoc signatures have a different designated requirement after every
        // build. On macOS this can make UNUserNotificationCenter report the app
        // as unavailable instead of presenting its authorization sheet. Keep the
        // modern API for stable Apple-signed builds and use the built-in macOS
        // compatibility center for freely distributed ad-hoc builds.
        if usesLegacyDelivery {
            UserDefaults.standard.set(true, forKey: notificationsEnabledKey)
            completion(true, false)
            return
        }

        guard !authorizationRequestInFlight else { return }
        authorizationRequestInFlight = true

        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                finishAuthorization(
                    granted: true,
                    shouldOpenSettings: false,
                    completion: completion
                )

            case .notDetermined:
                do {
                    let granted = try await center.requestAuthorization(
                        options: [.alert, .sound]
                    )
                    finishAuthorization(
                        granted: granted,
                        shouldOpenSettings: false,
                        completion: completion
                    )
                } catch {
                    finishAuthorization(
                        granted: false,
                        shouldOpenSettings: false,
                        completion: completion
                    )
                }

            case .denied:
                finishAuthorization(
                    granted: false,
                    shouldOpenSettings: true,
                    completion: completion
                )

            @unknown default:
                finishAuthorization(
                    granted: false,
                    shouldOpenSettings: false,
                    completion: completion
                )
            }
        }
    }

    func synchronizeEnabledState(completion: @escaping (Bool) -> Void) {
        if usesLegacyDelivery {
            completion(UserDefaults.standard.bool(forKey: notificationsEnabledKey))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            let enabled: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                enabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
            case .notDetermined, .denied:
                enabled = false
            @unknown default:
                enabled = false
            }
            UserDefaults.standard.set(enabled, forKey: notificationsEnabledKey)
            completion(enabled)
        }
    }

    func send(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: notificationsEnabledKey) else {
            return
        }

        if usesLegacyDelivery {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                try? await center.add(
                    UNNotificationRequest(
                        identifier: UUID().uuidString,
                        content: content,
                        trigger: nil
                    )
                )

            case .notDetermined, .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func finishAuthorization(
        granted: Bool,
        shouldOpenSettings: Bool,
        completion: @escaping (_ enabled: Bool, _ shouldOpenSettings: Bool) -> Void
    ) {
        authorizationRequestInFlight = false
        UserDefaults.standard.set(granted, forKey: notificationsEnabledKey)
        completion(granted, shouldOpenSettings)
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
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}

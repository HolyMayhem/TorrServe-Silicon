import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}
let states: [NotificationAuthorizationState] = [.unknown, .notDetermined, .authorized, .provisional, .denied, .legacyUnknown]
for state in states {
    expect(NotificationDeliveryPolicy.blockedResult(enabled: false, eventEnabled: true, authorization: state) == .appDisabled, "App preference must always suppress delivery")
    expect(NotificationDeliveryPolicy.blockedResult(enabled: true, eventEnabled: false, authorization: state) == .eventDisabled, "Per-event preference must suppress delivery")
}
expect(NotificationDeliveryPolicy.blockedResult(enabled: true, eventEnabled: true, authorization: .denied) == .systemBlocked, "A system denial must not be treated as delivery")
expect(NotificationDeliveryPolicy.blockedResult(enabled: true, eventEnabled: true, authorization: .notDetermined) == .authorizationRequired, "Undetermined authorization")
expect(NotificationDeliveryPolicy.blockedResult(enabled: true, eventEnabled: true, authorization: .unknown) == .authorizationRequired, "Unknown modern authorization")
for state in [NotificationAuthorizationState.authorized, .provisional, .legacyUnknown] {
    expect(NotificationDeliveryPolicy.blockedResult(enabled: true, eventEnabled: true, authorization: state) == nil, "Allowed submissions")
}
let suite = "TorrServeNotificationTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
AppNotificationPreferences.registerDefaults(in: defaults)
var preferences = AppNotificationPreferences.load(from: defaults)
expect(preferences.playsSound, "Default sound")
for event in AppNotificationEvent.allCases {
    expect(preferences[event], "Each event is enabled by default")
    for isRussian in [true, false] {
        expect(!event.displayTitle(isRussian: isRussian).isEmpty, "Every event has a test title")
        expect(!event.testBody(isRussian: isRussian).isEmpty, "Every event has safe test content")
    }
    preferences[event] = false
}
preferences.playsSound = false
preferences.save(to: defaults)
let reloaded = AppNotificationPreferences.load(from: defaults)
expect(!reloaded.playsSound, "Sound preference persists")
for event in AppNotificationEvent.allCases { expect(!reloaded[event], "Each event preference persists") }
let results: [NotificationDeliveryResult] = [.accepted, .legacyDelivered, .legacyUnconfirmed, .appDisabled, .eventDisabled, .systemBlocked, .authorizationRequired, .failed("Sample error")]
for result in results {
    for isRussian in [true, false] { expect(!result.message(isRussian: isRussian).isEmpty, "All outcomes have visible feedback") }
}
expect(NotificationDeliveryResult.legacyUnconfirmed.isFailure, "Unconfirmed legacy delivery must not show success")
expect(!NotificationDeliveryResult.accepted.isFailure, "Accepted submission")
expect(NotificationSystemState(authorization: .legacyUnknown).bannersEnabled == nil, "Legacy system settings must remain unknown")
print("Notifications: \(checks) checks passed")

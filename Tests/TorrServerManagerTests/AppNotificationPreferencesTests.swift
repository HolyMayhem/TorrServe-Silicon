import Foundation
import XCTest
@testable import TorrServerManager

final class AppNotificationPreferencesTests: XCTestCase {
    func testRegisteredDefaultsEnableEveryEventAndSound() {
        withUserDefaults { userDefaults in
            AppNotificationPreferences.registerDefaults(in: userDefaults)

            let preferences = AppNotificationPreferences.load(from: userDefaults)

            XCTAssertTrue(preferences.playsSound)
            for event in AppNotificationEvent.allCases {
                XCTAssertTrue(preferences[event], "Expected \(event.rawValue) to be enabled")
            }
        }
    }

    func testRoundTripsIndividualEventAndSoundChoices() {
        withUserDefaults { userDefaults in
            AppNotificationPreferences.registerDefaults(in: userDefaults)
            var preferences = AppNotificationPreferences.load(from: userDefaults)
            preferences.playsSound = false
            preferences[.serverStarted] = false
            preferences[.offlineDownloadFailed] = false

            preferences.save(to: userDefaults)
            let restored = AppNotificationPreferences.load(from: userDefaults)

            XCTAssertFalse(restored.playsSound)
            XCTAssertFalse(restored[.serverStarted])
            XCTAssertFalse(restored[.offlineDownloadFailed])
            XCTAssertTrue(restored[.serverStopped])
            XCTAssertTrue(restored[.offlineDownloadCompleted])
        }
    }

    func testRegisteringDefaultsDoesNotOverwriteSavedChoices() {
        withUserDefaults { userDefaults in
            AppNotificationPreferences.registerDefaults(in: userDefaults)
            var preferences = AppNotificationPreferences.load(from: userDefaults)
            preferences[.torrServerUpdated] = false
            preferences.save(to: userDefaults)

            AppNotificationPreferences.registerDefaults(in: userDefaults)

            XCTAssertFalse(
                AppNotificationPreferences.load(from: userDefaults)[.torrServerUpdated]
            )
        }
    }

    private func withUserDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "AppNotificationPreferencesTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        body(userDefaults)
    }
}

import AppKit

@MainActor
extension AppDelegate {
    func refreshNotificationStatus() {
        guard !isNotificationAuthorizationPending else { return }
        notificationController.synchronizeEnabledState { [weak self] enabled in
            self?.mainWindowModel.notificationsEnabled = enabled
        }
    }

    @objc func toggleDeveloperMenu(_ sender: Any?) {
        mainWindowModel.developerMenuEnabled.toggle()
        if mainWindowModel.developerMenuEnabled {
            showSettingsWindow(category: .developer)
        } else if settingsNavigationModel.selectedCategory == .developer {
            settingsNavigationModel.selectedCategory = .general
        }
        buildMainMenu()
    }

    func sendTestNotification(_ event: AppNotificationEvent) {
        guard mainWindowModel.developerMenuEnabled,
              !mainWindowModel.notificationTestsInFlight.contains(event) else { return }
        mainWindowModel.notificationTestsInFlight.insert(event)
        mainWindowModel.notificationTestResults[event] = nil
        let isRussian = currentLanguage == .russian
        notificationController.send(
            event: event,
            title: (isRussian ? "Тест: " : "Test: ") + event.displayTitle(isRussian: isRussian),
            body: event.testBody(isRussian: isRussian)
        ) { [weak self] result in
            self?.mainWindowModel.notificationTestsInFlight.remove(event)
            self?.mainWindowModel.notificationTestResults[event] = result
        }
    }
}

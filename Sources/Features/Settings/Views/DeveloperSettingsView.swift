import SwiftUI

struct NotificationSettingsStatusView: View {
    @ObservedObject var model: MainWindowModel
    private var isRussian: Bool { model.language == .russian }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isRussian ? "Разрешение macOS" : "macOS authorization")
                .font(.callout.weight(.medium))
            Text(model.notificationSystemState.message(isRussian: isRussian))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.notificationSystemState.soundsEnabled == false {
                Text(isRussian ? "Звук отключён в настройках уведомлений macOS." : "Sound is disabled in macOS notification settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let result = model.lastNotificationResult, case .failed(let error) = result {
                Text(isRussian ? "Последняя ошибка отправки: \(error)" : "Last delivery error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            HStack {
                Button(isRussian ? "Открыть настройки macOS" : "Open macOS Settings") {
                    model.onOpenNotificationSettings?()
                }
                Button(isRussian ? "Обновить статус" : "Refresh status") {
                    model.onRefreshNotificationStatus?()
                }
                .disabled(model.notificationsAuthorizationPending)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 12)
        .searchableSetting(isRussian ? "Разрешение macOS" : "macOS authorization")
    }
}

struct DeveloperSettingsView: View {
    @ObservedObject var model: MainWindowModel
    private var isRussian: Bool { model.language == .russian }

    var body: some View {
        VStack(spacing: SettingsScreenLayout.sectionSpacing) {
            MatrixDowngradeSettingsView(model: model)

            ServerSettingsGroup(title: isRussian ? "Системные уведомления" : "System notifications") {
                NotificationSettingsStatusView(model: model)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.notificationsEnabled
                        ? (isRussian ? "Уведомления приложения включены." : "App notifications are enabled.")
                        : (isRussian ? "Уведомления приложения выключены. Включите их в разделе «Основные»." : "App notifications are disabled. Enable them in General."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(isRussian ? "Открыть основные настройки" : "Open General settings") {
                        model.onOpenSettings?(.general)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 12)
                .searchableSetting(isRussian ? "Уведомления приложения" : "App notifications")
            }

            ServerSettingsGroup(
                title: isRussian ? "Тестовые уведомления" : "Test notifications",
                footer: isRussian
                    ? "Тесты учитывают общий переключатель, выбранные события и звук. Сервер, файлы и обновления не изменяются. Подтверждение отправки не гарантирует показ баннера: на него влияют настройки macOS и фокусирование."
                    : "Tests respect app, event and sound preferences. Server state, files and updates are unchanged. Submission does not guarantee a banner: macOS settings and Focus still apply."
            ) {
                ForEach(AppNotificationEvent.allCases) { event in
                    if event != AppNotificationEvent.allCases.first { Divider() }
                    testRow(event)
                }
            }
        }
    }

    private func testRow(_ event: AppNotificationEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(event.displayTitle(isRussian: isRussian))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if model.notificationTestsInFlight.contains(event) {
                    ProgressView().controlSize(.small)
                }
                Button(isRussian ? "Отправить тест" : "Send test") {
                    model.onSendTestNotification?(event)
                }
                .controlSize(.small)
                .disabled(model.notificationTestsInFlight.contains(event))
            }
            if let result = model.notificationTestResults[event] {
                Text(result.message(isRussian: isRussian))
                    .font(.caption)
                    .foregroundStyle(result.isFailure ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 12)
        .searchableSetting(event.displayTitle(isRussian: isRussian))
    }
}

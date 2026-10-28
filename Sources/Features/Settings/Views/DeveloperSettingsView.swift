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
                if model.notificationSystemState.authorization == .notDetermined {
                    Button(isRussian ? "Разрешить уведомления" : "Allow notifications") {
                        model.onNotificationsChanged?(true)
                    }
                    .disabled(model.notificationsAuthorizationPending)
                }
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
            ServerSettingsGroup(title: isRussian ? "Окно «Что нового»" : "What’s New window") {
                VStack(alignment: .leading, spacing: 8) {
                    Button(isRussian ? "Показать предпросмотр" : "Show preview") {
                        model.onPreviewWhatsNew?()
                    }
                    .disabled(!model.canPreviewWhatsNew)
                    Text(isRussian
                        ? "Предпросмотр работает и при выключенном автопоказе и не отмечает объявление просмотренным."
                        : "Preview works with automatic presentation disabled and does not mark the announcement as seen.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = model.whatsNewPreviewError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 12)
                .searchableSetting(isRussian ? "Предпросмотр «Что нового»" : "What’s New preview")
            }

            OfflineDownloadsPreviewControls(model: model, preview: model.offlineDownloadsPreview)

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

private struct OfflineDownloadsPreviewControls: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var preview: OfflineDownloadsPreview
    private var isRussian: Bool { model.language == .russian }

    var body: some View {
        ServerSettingsGroup(
            title: isRussian ? "Демо-материалы офлайн" : "Offline demo downloads",
            footer: isRussian
                ? "Добавляет 15 материалов: 12 фильмов и 3 сериала с сериями по сезонам. Видео не скачиваются. Демо исчезнет после перезапуска; настоящие загрузки сохранятся."
                : "Adds 15 titles: 12 movies and 3 series with episodes grouped by season. No videos are downloaded. Demo data disappears after restarting; real downloads are retained."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(isRussian ? "Заполнить офлайн демо-материалами" : "Fill Offline with demo titles") {
                        preview.populate(isRussian: isRussian)
                        model.onOpenOfflinePreview?()
                    }
                    Button(isRussian ? "Очистить демо-материалы" : "Clear demo downloads") {
                        preview.clear()
                    }
                    .disabled(preview.records.isEmpty)
                }
                .controlSize(.small)

                if !preview.records.isEmpty {
                    Text(isRussian ? "Демо-материалов: \(OfflineMediaLibrary.groups(records: preview.records).count)" : "Demo items: \(OfflineMediaLibrary.groups(records: preview.records).count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .searchableSetting(isRussian ? "Демо-материалы офлайн" : "Offline demo downloads")
        }
    }
}

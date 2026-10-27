import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var offlineDownloadManager: OfflineDownloadManager
    let category: SettingsCategory
    var isSearchIndex = false
    @Environment(\.isIndexingSettings) private var isIndexing
    @State private var offlineDownloadError: String?
    @State private var offlineDownloadErrorTitle: String?
    @State private var pendingOfflineDownloadDeletion: OfflineDownloadRecord?

    private let pickerColumnWidth: CGFloat = 190

    private var texts: Texts { Texts(language: model.language) }

    var body: some View {
        if isSearchIndex {
            categorySections
        } else {
            pageContent
        }
    }

    private var pageContent: some View {
        SettingsSearchScrollView {
            VStack(spacing: SettingsScreenLayout.sectionSpacing) {
                categorySections
            }
            .padding(.horizontal, SettingsScreenLayout.formContentInset)
            .padding(.top, SettingsScreenLayout.scrollContentTopPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: SettingsScreenLayout.contentMaxWidth)
        .padding(.horizontal, SettingsScreenLayout.horizontalPadding)
        .padding(.top, SettingsScreenLayout.topPadding)
        .padding(.bottom, SettingsScreenLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if category == .downloads {
                offlineDownloadManager.refreshCompletedDownloads()
            }
        }
        .alert(
            offlineDownloadErrorTitle
                ?? (model.language == .russian ? "Ошибка" : "Error"),
            isPresented: Binding(
                get: { offlineDownloadError != nil },
                set: { isPresented in
                    if !isPresented {
                        offlineDownloadError = nil
                        offlineDownloadErrorTitle = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(offlineDownloadError ?? "")
        }
        .confirmationDialog(
            model.language == .russian
                ? "Удалить загруженный фильм?"
                : "Delete downloaded movie?",
            isPresented: Binding(
                get: { pendingOfflineDownloadDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingOfflineDownloadDeletion = nil
                    }
                }
            )
        ) {
            Button(
                model.language == .russian ? "Удалить" : "Delete",
                role: .destructive
            ) {
                deletePendingOfflineDownload()
            }
            Button(model.language == .russian ? "Отмена" : "Cancel", role: .cancel) {
                pendingOfflineDownloadDeletion = nil
            }
        } message: {
            Text(pendingOfflineDownloadDeletion?.destinationURL.lastPathComponent ?? "")
        }
    }

    @ViewBuilder
    private var categorySections: some View {
        switch category {
        case .general:
            applicationSection
            notificationsSection
        case .interface:
            interfaceSection
        case .menuBar:
            menuBarSection
        case .updates:
            torrServerUpdatesSection
            appUpdatesSection
        case .downloads:
            offlineDownloadsSection
        case .metadata:
            metadataSection
            if model.metadataSource != .disabled {
                animeMetadataSection
            }
        case .keyboard:
            KeyboardShortcutsSettingsView(language: model.language)
        case .developer:
            if model.developerMenuEnabled { DeveloperSettingsView(model: model) }
        case .server:
            EmptyView()
        }
    }

    private var applicationSection: some View {
        settingsSection(title: model.language == .russian ? "Запуск и поведение" : "Startup & Behavior") {
            toggleRow(
                texts.launchAtLogin,
                keyPath: \.launchAtLogin,
                callback: model.onLaunchAtLoginChanged
            )
            Divider()
            toggleRow(
                texts.autoStartServer,
                keyPath: \.autoStartServer,
                callback: model.onAutoStartChanged
            )
            Divider()
            toggleRow(
                texts.hideDockIcon,
                keyPath: \.hideDockIcon,
                callback: model.onHideDockIconChanged
            )
            .disabled(!model.menuBarPreferences.isIconVisible)
        }
    }

    private var notificationsSection: some View {
        VStack(spacing: SettingsScreenLayout.sectionSpacing) {
            settingsSection(
                title: model.language == .russian ? "Уведомления" : "Notifications",
                footer: model.language == .russian
                    ? "Показ уведомлений также должен быть разрешён в настройках macOS."
                    : "Notifications must also be allowed in macOS Settings."
            ) {
                notificationPreferenceRow(
                    systemImage: "bell.fill",
                    title: model.language == .russian ? "Уведомления приложения" : "App notifications",
                    detail: model.language == .russian ? "Загрузки, состояние сервера и обновления." : "Downloads, server status, and updates.",
                    isOn: setting(\.notificationsEnabled, callback: model.onNotificationsChanged)
                )
                .disabled(model.notificationsAuthorizationPending)
                Divider()
                notificationPreferenceRow(
                    systemImage: "speaker.wave.2.fill",
                    title: model.language == .russian ? "Звук уведомлений" : "Notification sound",
                    detail: model.language == .russian ? "Воспроизводить системный звук." : "Play the system notification sound.",
                    isOn: notificationSoundBinding
                )
                .disabled(notificationDetailsDisabled)
                Divider()
                NotificationSettingsStatusView(model: model)
            }

            settingsSection(title: model.language == .russian ? "События" : "Events") {
                ForEach(AppNotificationEvent.allCases) { event in
                    if event != AppNotificationEvent.allCases.first { Divider() }
                    notificationPreferenceRow(
                        systemImage: notificationEventIcon(event),
                        title: notificationEventTitle(event),
                        detail: notificationEventDetail(event),
                        isOn: notificationEventBinding(event)
                    )
                    .disabled(notificationDetailsDisabled)
                }
            }
        }
    }

    private var menuBarSection: some View {
        VStack(spacing: SettingsScreenLayout.sectionSpacing) {
            settingsSection(title: model.language == .russian ? "Значок и скорость" : "Icon & Speed", footer: texts.menuBarSettingsFooter) {
                menuBarToggleRow(texts.showMenuBarIcon, keyPath: \.isIconVisible)
                Divider()
                menuBarToggleRow(texts.showSpeed, keyPath: \.showsSpeed)
                Divider()
                settingRow(texts.speedFormat) {
                    Picker(texts.speedFormat, selection: $model.speedUnit) {
                        Text(texts.automaticSpeed).tag(SpeedDisplayUnit.automatic)
                        Text(texts.megabytesSpeed).tag(SpeedDisplayUnit.megabytes)
                        Text(texts.megabitsSpeed).tag(SpeedDisplayUnit.megabits)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: pickerColumnWidth, alignment: .trailing)
                    .onChange(of: model.speedUnit) { _, unit in model.onSpeedUnitChanged?(unit) }
                }
            }
            settingsSection(title: model.language == .russian ? "Содержимое меню" : "Menu Content") {
                menuBarToggleRow(texts.showRecentMaterial, keyPath: \.showsRecentMaterial)
                Divider()
                menuBarToggleRow(texts.showQuickActions, keyPath: \.showsQuickActions)
                Divider()
                menuBarToggleRow(texts.showQRCodeInMenu, keyPath: \.showsQRCode)
                Divider()
                menuBarToggleRow(texts.expandQRCodeOnOpen, keyPath: \.expandsQRCodeOnOpen)
                    .disabled(!model.menuBarPreferences.showsQRCode)
            }
            settingsSection(
                title: model.language == .russian ? "Дополнительные элементы" : "Additional items",
                footer: model.language == .russian
                    ? "Каждый элемент включается отдельно. Их расположение меняется ниже, вместе с остальными блоками меню."
                    : "Enable each item separately. Reorder them below along with the other menu sections."
            ) {
                ForEach(MenuBarExtraOption.allCases) { option in
                    if option != MenuBarExtraOption.allCases.first { Divider() }
                    menuBarToggleRow(option.title(language: model.language), keyPath: option.keyPath)
                }
            }
            settingsSection(title: texts.menuBarElementOrder) { menuBarOrderRow }
        }
    }

    private var torrServerUpdatesSection: some View {
        settingsSection(
            title: "TorrServer MatriX",
            footer: model.language == .russian
                ? "Рабочая версия сохраняется. При неудачном запуске обновления приложение вернётся к предыдущей."
                : "The working version is kept. If the update cannot start, the app restores the previous version."
        ) {
            settingRow(model.language == .russian ? "Установленная версия" : "Installed version") {
                Text(model.torrServerVersion ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Divider()
            if let activity = model.torrServerUpdateActivity {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.detail(language: model.language)).font(.callout)
                    TorrServerUpdateProgressBar(progress: activity.clampedProgress)
                }
                .padding(.vertical, 14)
            } else if let update = model.torrServerUpdate {
                settingRow(model.language == .russian ? "Доступна \(update.latestVersion)" : "Available: \(update.latestVersion)") {
                    Button(model.language == .russian ? "Установить" : "Install") { model.onInstallTorrServerUpdate?() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canInstallTorrServerUpdate)
                }
            } else {
                settingRow(model.language == .russian ? "Проверка обновлений" : "Check for updates") {
                    HStack(spacing: 8) {
                        if model.isCheckingForTorrServerUpdates { ProgressView().controlSize(.small) }
                        Button(model.language == .russian ? "Проверить сейчас" : "Check Now") { model.onCheckForTorrServerUpdates?() }
                            .disabled(model.isCheckingForTorrServerUpdates || model.statusKind == .working)
                    }
                }
            }
            Divider()
            toggleRow(texts.autoUpdateTorrServer, keyPath: \.autoUpdateTorrServer, callback: model.onAutoUpdateTorrServerChanged)
            if model.matrixDowngradeTestActive {
                Divider()
                MatrixUpdateTestStatusView(model: model)
            }
        }
    }

    private var appUpdatesSection: some View {
        settingsSection(
            title: model.language == .russian
                ? "Обновления TorrServe Silicon"
                : "TorrServe Silicon Updates",
            footer: model.language == .russian
                ? "Обновления интерфейса и встроенных компонентов приложения."
                : "Updates to the interface and the app’s bundled components."
        ) {
            toggleRow(
                model.language == .russian
                    ? "Автоматически проверять обновления"
                    : "Automatically check for updates",
                keyPath: \.automaticallyChecksForAppUpdates,
                callback: model.onAutomaticallyChecksForAppUpdatesChanged
            )
            Divider()
            toggleRow(
                model.language == .russian
                    ? "Автоматически загружать и устанавливать"
                    : "Automatically download and install",
                keyPath: \.automaticallyDownloadsAppUpdates,
                callback: model.onAutomaticallyDownloadsAppUpdatesChanged
            )
            .disabled(!model.automaticallyChecksForAppUpdates)
            Divider()
            settingRow(
                model.language == .russian ? "Обновление приложения" : "Application update"
            ) {
                Button(model.language == .russian ? "Проверить сейчас" : "Check Now") {
                    model.onCheckForAppUpdates?()
                }
                .disabled(!model.canCheckForAppUpdates)
            }
        }
    }

    @ViewBuilder
    private var offlineDownloadsSection: some View {
        settingsSection(
            title: model.language == .russian
                ? "Офлайн-загрузки"
                : "Offline Downloads",
            footer: model.language == .russian
                ? "Файлы хранятся отдельно от приложения и не удаляются при обновлении TorrServe Silicon."
                : "Files are stored outside the app and remain in place when TorrServe Silicon is updated."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(model.language == .russian ? "Папка загрузок" : "Download folder", systemImage: "folder")
                    Spacer()
                    Button(model.language == .russian ? "Выбрать…" : "Choose…") { chooseOfflineDownloadFolder() }
                }
                Text(offlineDownloadFolderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(offlineDownloadFolderPath)
            }
            .padding(.vertical, 12)
            .searchableSetting(model.language == .russian ? "Папка загрузок" : "Download folder")
        }

        settingsSection(
            title: model.language == .russian
                ? "Загруженные фильмы"
                : "Downloaded Movies",
            footer: completedOfflineDownloadsFooter
        ) {
            if isIndexing {
                EmptyView()
            } else if completedOfflineDownloads.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(model.language == .russian
                        ? "Загруженных фильмов пока нет"
                        : "No downloaded movies yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .frame(minHeight: 52)
            } else {
                ForEach(completedOfflineDownloads, id: \.destinationURL) { record in
                    completedOfflineDownloadRow(record)

                    if record.destinationURL
                        != completedOfflineDownloads.last?.destinationURL {
                        Divider()
                    }
                }
            }
        }
    }

    private var completedOfflineDownloads: [OfflineDownloadRecord] {
        offlineDownloadManager.completedDownloads.sorted {
            $0.completedAt > $1.completedAt
        }
    }

    private var completedOfflineDownloadsFooter: String {
        guard !completedOfflineDownloads.isEmpty else {
            return model.language == .russian
                ? "Завершённые офлайн-загрузки появятся здесь."
                : "Completed offline downloads will appear here."
        }

        let totalSize = completedOfflineDownloads.reduce(Int64(0)) {
            $0 + $1.expectedLength
        }
        let size = ByteCountFormatter.string(
            fromByteCount: totalSize,
            countStyle: .file
        )
        return model.language == .russian
            ? "Всего файлов: \(completedOfflineDownloads.count) · \(size)"
            : "Total files: \(completedOfflineDownloads.count) · \(size)"
    }

    private func completedOfflineDownloadRow(
        _ record: OfflineDownloadRecord
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 22)

            Text(record.destinationURL.lastPathComponent)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(record.destinationURL.path)

            Spacer(minLength: 12)

            Text(ByteCountFormatter.string(
                fromByteCount: record.expectedLength,
                countStyle: .file
            ))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()

            Button {
                playOfflineDownload(record)
            } label: {
                Label(
                    model.language == .russian ? "Смотреть" : "Watch",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                pendingOfflineDownloadDeletion = record
            } label: {
                Label(
                    model.language == .russian ? "Удалить" : "Delete",
                    systemImage: "trash"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(minHeight: 48)
    }

    private var offlineDownloadFolderPath: String {
        offlineDownloadManager.downloadDirectoryURL?.path
            ?? (model.language == .russian ? "Папка недоступна" : "Folder unavailable")
    }

    private func chooseOfflineDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = model.language == .russian
            ? "Выберите папку для офлайн-загрузок"
            : "Choose an Offline Download Folder"
        panel.prompt = model.language == .russian ? "Выбрать" : "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = offlineDownloadManager.downloadDirectoryURL

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        do {
            try offlineDownloadManager.setDownloadDirectory(directoryURL)
        } catch {
            offlineDownloadErrorTitle = model.language == .russian
                ? "Не удалось выбрать папку"
                : "Could Not Select Folder"
            offlineDownloadError = error.localizedDescription
        }
    }

    private func playOfflineDownload(_ record: OfflineDownloadRecord) {
        do {
            try ExternalPlayerLauncher.open(
                record.destinationURL,
                using: model.preferredPlayer,
                customPlayerPath: UserDefaults.standard.string(
                    forKey: libraryCustomPlayerPathKey
                ) ?? ""
            )
        } catch {
            offlineDownloadErrorTitle = model.language == .russian
                ? "Не удалось открыть фильм"
                : "Could Not Open Movie"
            offlineDownloadError = error.localizedDescription
        }
    }

    private func deletePendingOfflineDownload() {
        guard let record = pendingOfflineDownloadDeletion else { return }
        pendingOfflineDownloadDeletion = nil

        do {
            try offlineDownloadManager.moveCompletedDownloadToTrash(
                sourceURL: record.sourceURL,
                expectedLength: record.expectedLength
            )
        } catch {
            offlineDownloadErrorTitle = model.language == .russian
                ? "Не удалось удалить фильм"
                : "Could Not Delete Movie"
            offlineDownloadError = error.localizedDescription
        }
    }

    private var menuBarOrderRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(texts.menuBarOrderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.menuBarPreferences.sectionOrder
                    != MenuBarPopoverSection.allCases {
                    Button(model.language == .russian ? "По умолчанию" : "Default") {
                        var preferences = model.menuBarPreferences
                        preferences.sectionOrder = MenuBarPopoverSection.allCases
                        commitMenuBarPreferences(preferences)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            MenuBarSectionOrderView(
                sections: model.menuBarPreferences.sectionOrder,
                preferences: model.menuBarPreferences,
                language: model.language
            ) { sections in
                var preferences = model.menuBarPreferences
                preferences.sectionOrder = sections
                commitMenuBarPreferences(preferences)
            }

        }
        .padding(.vertical, 10)
        .searchableSetting(texts.menuBarElementOrder)
    }

    private var interfaceSection: some View {
        VStack(spacing: SettingsScreenLayout.sectionSpacing) {
            settingsSection(title: model.language == .russian ? "Интерфейс" : "Interface") {
                settingRow(texts.languageLabel) {
                    Picker(texts.languageLabel, selection: $model.language) {
                        Text("Русский").tag(AppLanguage.russian)
                        Text("English").tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: pickerColumnWidth, alignment: .trailing)
                    .onChange(of: model.language) { _, language in model.onLanguageChanged?(language) }
                }
            }
            settingsSection(
                title: model.language == .russian ? "Поиск торрентов" : "Torrent Search",
                footer: model.language == .russian
                    ? "TorrentSearch работает без отдельного сервера. Jackett можно подключить отдельно или использовать вместе с ним."
                    : "TorrentSearch needs no separate server. Connect Jackett as an alternative or search both together."
            ) {
                toggleRow(
                    model.language == .russian ? "Показывать раздел поиска" : "Show Search",
                    keyPath: \.jackettEnabled,
                    callback: model.onJackettEnabledChanged
                )
                Divider()
                settingRow(model.language == .russian ? "TorrentSearch и Jackett" : "TorrentSearch & Jackett") {
                    Button(model.language == .russian ? "Настроить источники…" : "Configure Sources…") { model.onConfigureSearch?() }
                        .disabled(!model.jackettEnabled)
                }
            }
        }
    }

    private var metadataSection: some View {
        settingsSection(
            title: model.language == .russian ? "Метаданные" : "Metadata",
            footer: metadataFooter
        ) {
            settingRow(texts.metadataProvider) {
                Picker("", selection: $model.metadataSource) {
                    ForEach(MetadataSourceMode.allCases, id: \.self) { source in
                        Text(metadataSourceTitle(source)).tag(source)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(width: pickerColumnWidth, alignment: .trailing)
                .onChange(of: model.metadataSource) { _, source in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        model.onMetadataSourceChanged?(source)
                    }
                }
            }

            if model.metadataSource != .disabled {
                if model.metadataSource == .combined {
                    Divider()
                    combinedOrderRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                settingRow(model.language == .russian ? "Ключи API" : "API keys") {
                    Picker("", selection: $model.metadataAPIKeyMode) {
                        Text(model.language == .russian ? "Встроенные" : "Built-in")
                            .tag(MetadataAPIKeyMode.builtIn)
                        Text(model.language == .russian ? "Свои" : "Custom")
                            .tag(MetadataAPIKeyMode.custom)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: pickerColumnWidth, alignment: .trailing)
                    .onChange(of: model.metadataAPIKeyMode) { _, mode in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            model.onMetadataAPIKeyModeChanged?(mode)
                        }
                    }
                }

                if model.metadataAPIKeyMode == .custom {
                    Divider()
                    apiKeyRow("TMDB API Key", provider: .tmdb, value: $model.tmdbAPIKey)
                    Divider()
                    apiKeyRow("OMDb API Key", provider: .omdb, value: $model.omdbAPIKey)
                    Divider()
                    apiKeyRow("КиноПоиск API Key", provider: .kinopoisk, value: $model.kinopoiskAPIKey)
                }

                Divider()
                settingRow(model.language == .russian ? "Перевод описаний" : "Overview translation") {
                    Picker("", selection: $model.overviewTranslationMode) {
                        Text(model.language == .russian ? "Автоматически" : "Automatic")
                            .tag(OverviewTranslationMode.automatic)
                        Text(model.language == .russian ? "Оригинал" : "Original")
                            .tag(OverviewTranslationMode.original)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: pickerColumnWidth, alignment: .trailing)
                    .onChange(of: model.overviewTranslationMode) { _, mode in
                        model.onOverviewTranslationModeChanged?(mode)
                    }
                }
            }
        }
    }

    private var combinedOrderRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.language == .russian ? "Порядок поиска" : "Lookup order")
                .font(.subheadline.weight(.medium))

            MetadataProviderOrderView(
                providers: model.combinedMetadataOrder,
                language: model.language
            ) { providers in
                model.combinedMetadataOrder = providers
                model.onCombinedMetadataOrderChanged?(providers)
            }

            Text(model.language == .russian
                ? "Если источник не найдёт материал, приложение автоматически перейдёт к следующему. Перетащите источники, чтобы изменить приоритет."
                : "If a source cannot find the title, the app automatically tries the next one. Drag sources to change priority.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .searchableSetting(model.language == .russian ? "Порядок поиска" : "Lookup order")
    }

    private var animeMetadataSection: some View {
        settingsSection(
            title: model.language == .russian ? "Аниме" : "Anime",
            footer: model.language == .russian
                ? "AniList проверяется отдельно и не входит в общий порядок поиска. Приложение принимает точное совпадение названия, а при наличии года — также и года. Затем при необходимости используются обычные источники."
                : "AniList is checked separately and is not included in the general lookup order. The app requires an exact title match and, when present, the year as well, then falls back to regular providers when needed."
        ) {
            toggleRow(
                model.language == .russian ? "Метаданные AniList" : "AniList metadata",
                keyPath: \.aniListEnabled,
                callback: model.onAniListEnabledChanged
            )
        }
    }

    private func apiKeyRow(
        _ title: String,
        provider: MetadataProvider,
        value: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                apiKeyTestStatus(provider)
            }
            MetadataAPIKeyEditor(
                value: value,
                fieldLabel: title,
                testTitle: model.language == .russian ? "Тест" : "Test",
                isTesting: model.metadataAPIKeyTestStates[provider] == .testing,
                commit: { model.onMetadataAPIKeyChanged?(provider, $0) },
                test: { model.onTestMetadataAPIKey?(provider, $0) }
            )
        }
        .padding(.vertical, 12)
        .searchableSetting(title)
    }

    @ViewBuilder
    private func apiKeyTestStatus(_ provider: MetadataProvider) -> some View {
        let state = model.metadataAPIKeyTestStates[provider] ?? .idle
        Group {
            switch state {
            case .idle:
                Color.clear
            case .testing:
                ProgressView()
                    .controlSize(.small)
                    .help(model.language == .russian ? "Проверка ключа" : "Testing key")
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(model.language == .russian ? "Ключ работает" : "The key works")
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(model.language == .russian ? "Ключ не принят сервисом" : "The service rejected this key")
            case .rateLimited:
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .foregroundStyle(.orange)
                    .help(model.language == .russian
                        ? "Ключ принят, но лимит запросов OMDb исчерпан. Повторите проверку позже."
                        : "The key was accepted, but the OMDb request limit has been reached. Try again later.")
            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(model.language == .russian
                        ? "Не удалось связаться с сервисом. Попробуйте позже."
                        : "Could not contact the service. Try again later.")
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(apiKeyTestAccessibilityLabel(state))
    }

    private func apiKeyTestAccessibilityLabel(_ state: MetadataAPIKeyTestState) -> String {
        switch state {
        case .idle:
            return model.language == .russian ? "Ключ не проверен" : "Key not tested"
        case .testing:
            return model.language == .russian ? "Ключ проверяется" : "Testing key"
        case .valid:
            return model.language == .russian ? "Ключ работает" : "Key is valid"
        case .invalid:
            return model.language == .russian ? "Ключ не работает" : "Key is invalid"
        case .rateLimited:
            return model.language == .russian
                ? "Ключ принят, лимит запросов исчерпан"
                : "Key accepted, request limit reached"
        case .unavailable:
            return model.language == .russian ? "Сервис недоступен" : "Service unavailable"
        }
    }

    private func metadataSourceTitle(_ source: MetadataSourceMode) -> String {
        switch source {
        case .disabled:
            return model.language == .russian ? "Не использовать" : "Off"
        case .combined:
            return model.language == .russian ? "Комбинированные" : "Combined"
        default:
            return source.displayName
        }
    }

    private var metadataFooter: String {
        if model.metadataSource == .disabled {
            return model.language == .russian
                ? "Новые метаданные не загружаются. Уже полученные карточки сохраняются."
                : "New metadata is not fetched. Previously loaded cards are kept."
        }
        if model.metadataAPIKeyMode == .builtIn {
            return model.language == .russian
                ? "Приложение использует встроенные ключи. В комбинированном режиме источники проверяются по указанному порядку."
                : "The app uses its built-in keys. Combined mode checks providers in the displayed order."
        }
        return model.language == .russian
            ? "Собственные ключи хранятся локально и используются только для получения постеров и описаний."
            : "Custom keys are stored locally and used only to fetch posters and descriptions."
    }

    private func toggleRow(
        _ title: String,
        keyPath: ReferenceWritableKeyPath<MainWindowModel, Bool>,
        callback: ((Bool) -> Void)?
    ) -> some View {
        settingRow(title) {
            Toggle("", isOn: setting(keyPath, callback: callback))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }

    private var notificationDetailsDisabled: Bool {
        !model.notificationsEnabled || model.notificationsAuthorizationPending
    }

    private var notificationSoundBinding: Binding<Bool> {
        Binding(
            get: { model.notificationPreferences.playsSound },
            set: { value in
                var preferences = model.notificationPreferences
                preferences.playsSound = value
                commitNotificationPreferences(preferences)
            }
        )
    }

    private func notificationEventBinding(_ event: AppNotificationEvent) -> Binding<Bool> {
        Binding(
            get: { model.notificationPreferences[event] },
            set: { value in
                var preferences = model.notificationPreferences
                preferences[event] = value
                commitNotificationPreferences(preferences)
            }
        )
    }

    private func commitNotificationPreferences(_ preferences: AppNotificationPreferences) {
        model.notificationPreferences = preferences
        model.onNotificationPreferencesChanged?(preferences)
    }

    private func notificationPreferenceRow(
        systemImage: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
        .frame(minHeight: 54)
        .searchableSetting(title)
    }

    private func notificationEventIcon(_ event: AppNotificationEvent) -> String {
        switch event {
        case .offlineDownloadCompleted:
            return "arrow.down.circle.fill"
        case .offlineDownloadFailed:
            return "exclamationmark.arrow.circlepath"
        case .serverStarted:
            return "play.circle.fill"
        case .serverStopped:
            return "stop.circle.fill"
        case .criticalError:
            return "exclamationmark.triangle.fill"
        case .torrServerUpdated:
            return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private func notificationEventTitle(_ event: AppNotificationEvent) -> String {
        event.displayTitle(isRussian: model.language == .russian)
    }

    private func notificationEventDetail(_ event: AppNotificationEvent) -> String {
        switch event {
        case .offlineDownloadCompleted:
            return model.language == .russian
                ? "Сообщать об окончании офлайн-загрузки."
                : "Notify when an offline download finishes."
        case .offlineDownloadFailed:
            return model.language == .russian
                ? "Сообщать, если офлайн-загрузку не удалось завершить."
                : "Notify when an offline download cannot be completed."
        case .serverStarted:
            return model.language == .russian
                ? "Сообщать, когда сервер готов к работе."
                : "Notify when the server is ready."
        case .serverStopped:
            return model.language == .russian
                ? "Сообщать о штатной остановке сервера."
                : "Notify when the server stops normally."
        case .criticalError:
            return model.language == .russian
                ? "Ошибки запуска сервера и установки обновлений."
                : "Server launch and update installation failures."
        case .torrServerUpdated:
            return model.language == .russian
                ? "Сообщать после установки или обновления движка."
                : "Notify after the engine is installed or updated."
        }
    }

    private func menuBarToggleRow(
        _ title: String,
        keyPath: WritableKeyPath<MenuBarPreferences, Bool>
    ) -> some View {
        settingRow(title) {
            Toggle("", isOn: Binding(
                get: { model.menuBarPreferences[keyPath: keyPath] },
                set: { value in
                    var preferences = model.menuBarPreferences
                    preferences[keyPath: keyPath] = value
                    commitMenuBarPreferences(preferences)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(title)
        }
    }

    private func commitMenuBarPreferences(_ preferences: MenuBarPreferences) {
        model.menuBarPreferences = preferences
        model.onMenuBarPreferencesChanged?(preferences)
    }

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 46)
        .padding(.vertical, 2)
        .searchableSetting(title)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ServerSettingsGroup(title: title, footer: footer, content: content)
    }

    private func setting(
        _ keyPath: ReferenceWritableKeyPath<MainWindowModel, Bool>,
        callback: ((Bool) -> Void)?
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { value in
                model[keyPath: keyPath] = value
                callback?(value)
            }
        )
    }
}

// Editing stays local until Return, focus loss, or the Test action. Saving each
// keystroke used to invalidate the entire library and persist incomplete keys.
private struct MetadataAPIKeyEditor: View {
    @Binding var value: String
    let fieldLabel: String
    let testTitle: String
    let isTesting: Bool
    let commit: (String) -> Void
    let test: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            SecureField(fieldLabel, text: $draft)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(minWidth: 160, maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .accessibilityLabel(fieldLabel)

            Button(testTitle) {
                commitDraft()
                test(draft)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize()
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { draft = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commitDraft() }
        }
        .onDisappear(perform: commitDraft)
    }

    private func commitDraft() {
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != value else { return }
        commit(normalized)
    }
}

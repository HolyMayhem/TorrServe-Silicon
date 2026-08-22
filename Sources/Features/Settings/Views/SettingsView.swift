import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MainWindowModel

    private let pickerColumnWidth: CGFloat = 220

    private var texts: Texts { Texts(language: model.language) }

    private var screenTitle: String {
        model.language == .russian ? "Общие настройки" : "General Settings"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsScreenLayout.sectionSpacing) {
                SettingsScreenTitle(title: screenTitle)

                SettingsIntroCard(
                    title: screenTitle,
                    message: model.language == .russian
                        ? "Настройте запуск приложения, уведомления, интерфейс, поиск и источники метаданных."
                        : "Configure app startup, notifications, interface, search, and metadata providers.",
                    systemImage: "gearshape.fill",
                    tint: .blue
                )

                applicationSection
                interfaceSection
                metadataSection
                if model.metadataSource != .disabled {
                    animeMetadataSection
                }
            }
            .padding(.horizontal, SettingsScreenLayout.formContentInset)
            .padding(.top, SettingsScreenLayout.scrollContentTopPadding)
            .padding(.bottom, 12)
        }
        .settingsScrollEdgeFade()
        .frame(maxWidth: SettingsScreenLayout.contentMaxWidth)
        .padding(.horizontal, SettingsScreenLayout.horizontalPadding)
        .padding(.top, SettingsScreenLayout.topPadding)
        .padding(.bottom, SettingsScreenLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var applicationSection: some View {
        settingsSection(title: model.language == .russian ? "Приложение" : "Application") {
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
                texts.autoUpdateTorrServer,
                keyPath: \.autoUpdateTorrServer,
                callback: model.onAutoUpdateTorrServerChanged
            )
            Divider()
            toggleRow(
                texts.showSpeed,
                keyPath: \.showSpeed,
                callback: model.onShowSpeedChanged
            )
            Divider()
            toggleRow(
                texts.hideDockIcon,
                keyPath: \.hideDockIcon,
                callback: model.onHideDockIconChanged
            )
            Divider()
            toggleRow(
                texts.notifications,
                keyPath: \.notificationsEnabled,
                callback: model.onNotificationsChanged
            )
            .disabled(model.notificationsAuthorizationPending)
        }
    }

    private var interfaceSection: some View {
        settingsSection(title: model.language == .russian ? "Интерфейс" : "Interface") {
            settingRow(texts.speedFormat) {
                Picker("", selection: $model.speedUnit) {
                    Text(texts.automaticSpeed).tag(SpeedDisplayUnit.automatic)
                    Text(texts.megabytesSpeed).tag(SpeedDisplayUnit.megabytes)
                    Text(texts.megabitsSpeed).tag(SpeedDisplayUnit.megabits)
                }
                .labelsHidden()
                .fixedSize()
                .frame(width: pickerColumnWidth, alignment: .trailing)
                .onChange(of: model.speedUnit) { _, unit in
                    model.onSpeedUnitChanged?(unit)
                }
            }
            Divider()
            settingRow(texts.languageLabel) {
                Picker("", selection: $model.language) {
                    Text(texts.russian).tag(AppLanguage.russian)
                    Text(texts.english).tag(AppLanguage.english)
                }
                .labelsHidden()
                .fixedSize()
                .frame(width: pickerColumnWidth, alignment: .trailing)
                .onChange(of: model.language) { _, language in
                    model.onLanguageChanged?(language)
                }
            }
            Divider()
            settingRow(texts.jackettSearch) {
                HStack(spacing: 6) {
                    if model.jackettEnabled {
                        Button {
                            model.onOpenJackettDashboard?()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help(model.language == .russian
                            ? "Открыть веб-панель Jackett"
                            : "Open Jackett web dashboard")
                        .accessibilityLabel(model.language == .russian
                            ? "Открыть веб-панель Jackett"
                            : "Open Jackett web dashboard")
                    }

                    Picker("", selection: $model.jackettEnabled) {
                        Text("Jackett").tag(true)
                        Text("Off").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: model.jackettEnabled) { _, isEnabled in
                        model.onJackettEnabledChanged?(isEnabled)
                    }
                }
                .frame(width: pickerColumnWidth, alignment: .trailing)
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
        settingRow(title) {
            HStack(spacing: 8) {
                apiKeyTestStatus(provider)

                Button(model.language == .russian ? "Тест" : "Test") {
                    model.onTestMetadataAPIKey?(provider, value.wrappedValue)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize()
                .disabled(
                    value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.metadataAPIKeyTestStates[provider] == .testing
                )

                SecureField(
                    "",
                    text: Binding(
                        get: { value.wrappedValue },
                        set: { newValue in
                            value.wrappedValue = newValue
                            model.onMetadataAPIKeyChanged?(provider, newValue)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(width: 300)
            }
        }
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
                ? "Приложение не будет загружать, хранить или показывать метаданные материалов."
                : "The app will not fetch, store, or display media metadata."
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
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 20)
            control()
        }
        .frame(minHeight: 42)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .generalSettingsPanel()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
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

private extension View {
    func generalSettingsPanel() -> some View {
        background(
            SettingsVisualStyle.panelBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

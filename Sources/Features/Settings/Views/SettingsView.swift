import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MainWindowModel

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
                .frame(width: 190)
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
                .frame(width: 190)
                .onChange(of: model.language) { _, language in
                    model.onLanguageChanged?(language)
                }
            }
            Divider()
            settingRow(texts.jackettSearch) {
                Picker("", selection: $model.jackettEnabled) {
                    Text("Jackett").tag(true)
                    Text("Off").tag(false)
                }
                .labelsHidden()
                .frame(width: 190)
                .onChange(of: model.jackettEnabled) { _, isEnabled in
                    model.onJackettEnabledChanged?(isEnabled)
                }
            }
        }
    }

    private var metadataSection: some View {
        settingsSection(
            title: model.language == .russian ? "Метаданные" : "Metadata",
            footer: model.language == .russian
                ? "Ключи хранятся локально и используются только для получения постеров и описаний."
                : "Keys are stored locally and used only to fetch posters and descriptions."
        ) {
            settingRow(texts.metadataProvider) {
                Picker("", selection: $model.metadataProvider) {
                    ForEach(MetadataProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .onChange(of: model.metadataProvider) { _, provider in
                    model.onMetadataProviderChanged?(provider)
                }
            }
            Divider()
            settingRow("TMDB API Key") {
                SecureField(
                    "",
                    text: Binding(
                        get: { model.tmdbAPIKey },
                        set: { value in
                            model.tmdbAPIKey = value
                            model.onMetadataAPIKeyChanged?(.tmdb, value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            }
            Divider()
            settingRow("OMDb API Key") {
                SecureField(
                    "",
                    text: Binding(
                        get: { model.omdbAPIKey },
                        set: { value in
                            model.omdbAPIKey = value
                            model.onMetadataAPIKeyChanged?(.omdb, value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
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
                .frame(width: 190)
                .onChange(of: model.overviewTranslationMode) { _, mode in
                    model.onOverviewTranslationModeChanged?(mode)
                }
            }
        }
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

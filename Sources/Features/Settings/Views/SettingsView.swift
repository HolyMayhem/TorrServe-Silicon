import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MainWindowModel

    private var texts: Texts { Texts(language: model.language) }

    var body: some View {
        Form {
            Section {
                Toggle(
                    texts.launchAtLogin,
                    isOn: setting(
                        \.launchAtLogin,
                        callback: model.onLaunchAtLoginChanged
                    )
                )
                Toggle(
                    texts.autoStartServer,
                    isOn: setting(
                        \.autoStartServer,
                        callback: model.onAutoStartChanged
                    )
                )
                Toggle(
                    texts.showSpeed,
                    isOn: setting(
                        \.showSpeed,
                        callback: model.onShowSpeedChanged
                    )
                )
                Toggle(
                    texts.hideDockIcon,
                    isOn: setting(
                        \.hideDockIcon,
                        callback: model.onHideDockIconChanged
                    )
                )
                Toggle(
                    texts.notifications,
                    isOn: setting(
                        \.notificationsEnabled,
                        callback: model.onNotificationsChanged
                    )
                )
                .disabled(model.notificationsAuthorizationPending)
            } header: {
                Text(model.language == .russian ? "Приложение" : "Application")
            }

            Section {
                Picker(texts.speedFormat, selection: $model.speedUnit) {
                    Text(texts.automaticSpeed).tag(SpeedDisplayUnit.automatic)
                    Text(texts.megabytesSpeed).tag(SpeedDisplayUnit.megabytes)
                    Text(texts.megabitsSpeed).tag(SpeedDisplayUnit.megabits)
                }
                .onChange(of: model.speedUnit) { _, unit in
                    model.onSpeedUnitChanged?(unit)
                }

                Picker(texts.languageLabel, selection: $model.language) {
                    Text(texts.russian).tag(AppLanguage.russian)
                    Text(texts.english).tag(AppLanguage.english)
                }
                .onChange(of: model.language) { _, language in
                    model.onLanguageChanged?(language)
                }

                Picker(texts.jackettSearch, selection: $model.jackettEnabled) {
                    Text("Jackett").tag(true)
                    Text("Off").tag(false)
                }
                .onChange(of: model.jackettEnabled) { _, isEnabled in
                    model.onJackettEnabledChanged?(isEnabled)
                }
            } header: {
                Text(model.language == .russian ? "Интерфейс" : "Interface")
            }

            Section {
                Picker(texts.metadataProvider, selection: $model.metadataProvider) {
                    ForEach(MetadataProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: model.metadataProvider) { _, provider in
                    model.onMetadataProviderChanged?(provider)
                }

                SecureField(
                    "TMDB API Key",
                    text: Binding(
                        get: { model.tmdbAPIKey },
                        set: { value in
                            model.tmdbAPIKey = value
                            model.onMetadataAPIKeyChanged?(.tmdb, value)
                        }
                    )
                )

                SecureField(
                    "OMDb API Key",
                    text: Binding(
                        get: { model.omdbAPIKey },
                        set: { value in
                            model.omdbAPIKey = value
                            model.onMetadataAPIKeyChanged?(.omdb, value)
                        }
                    )
                )

                Picker(
                    model.language == .russian ? "Перевод описаний" : "Overview translation",
                    selection: $model.overviewTranslationMode
                ) {
                    Text(model.language == .russian ? "Автоматически" : "Automatic")
                        .tag(OverviewTranslationMode.automatic)
                    Text(model.language == .russian ? "Оригинал" : "Original")
                        .tag(OverviewTranslationMode.original)
                }
                .onChange(of: model.overviewTranslationMode) { _, mode in
                    model.onOverviewTranslationModeChanged?(mode)
                }
            } header: {
                Text(model.language == .russian ? "Метаданные" : "Metadata")
            } footer: {
                Text(model.language == .russian
                    ? "Ключи хранятся локально и используются только для получения постеров и описаний."
                    : "Keys are stored locally and used only to fetch posters and descriptions.")
            }
        }
        .formStyle(.grouped)
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

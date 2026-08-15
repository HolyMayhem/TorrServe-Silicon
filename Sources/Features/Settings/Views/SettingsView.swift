import SwiftUI
import UniformTypeIdentifiers

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
                Picker("", selection: $model.jackettEnabled) {
                    Text("Jackett").tag(true)
                    Text("Off").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .frame(width: pickerColumnWidth, alignment: .trailing)
                .onChange(of: model.jackettEnabled) { _, isEnabled in
                    model.onJackettEnabledChanged?(isEnabled)
                }
            }
        }
    }

    private var metadataSection: some View {
        settingsSection(
            title: model.language == .russian ? "Метаданные" : "Metadata",
            footer: metadataFooter
        ) {
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

            if model.metadataSource == .combined {
                Divider()
                combinedOrderRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

    private func apiKeyRow(
        _ title: String,
        provider: MetadataProvider,
        value: Binding<String>
    ) -> some View {
        settingRow(title) {
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
            .frame(width: 320)
        }
    }

    private func metadataSourceTitle(_ source: MetadataSourceMode) -> String {
        guard source == .combined else { return source.displayName }
        return model.language == .russian ? "Комбинированные" : "Combined"
    }

    private var metadataFooter: String {
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

private struct MetadataProviderOrderView: View {
    let providers: [MetadataProvider]
    let language: AppLanguage
    let onChange: ([MetadataProvider]) -> Void
    @State private var draggedProvider: MetadataProvider?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                providerChip(provider)

                if index < providers.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerChip(_ provider: MetadataProvider) -> some View {
        Text(provider.displayName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(Capsule())
            .onDrag {
                draggedProvider = provider
                return NSItemProvider(object: provider.rawValue as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: MetadataProviderDropDelegate(
                    destination: provider,
                    providers: providers,
                    draggedProvider: $draggedProvider,
                    onChange: onChange
                )
            )
            .help(language == .russian
                ? "Перетащите, чтобы изменить приоритет"
                : "Drag to change priority")
            .accessibilityLabel(provider.displayName)
    }
}

private struct MetadataProviderDropDelegate: DropDelegate {
    let destination: MetadataProvider
    let providers: [MetadataProvider]
    @Binding var draggedProvider: MetadataProvider?
    let onChange: ([MetadataProvider]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedProvider,
              draggedProvider != destination,
              let sourceIndex = providers.firstIndex(of: draggedProvider),
              let destinationIndex = providers.firstIndex(of: destination) else {
            self.draggedProvider = nil
            return false
        }

        var updated = providers
        updated.remove(at: sourceIndex)
        updated.insert(draggedProvider, at: min(destinationIndex, updated.endIndex))
        self.draggedProvider = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            onChange(MetadataProviderSettings.normalizedOrder(updated))
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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

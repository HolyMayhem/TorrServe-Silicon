import AppKit
import SwiftUI


struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel
    @State private var showsClearCacheConfirmation = false
    @State private var showsDiagnostics = false
    @State private var showsMetadataSettings = false

    private var texts: Texts {
        Texts(language: model.language)
    }

    var body: some View {
        VStack(spacing: 10) {
            executableSection
            actionSection

            HStack(alignment: .top, spacing: 10) {
                storageSection
                    .frame(maxWidth: .infinity)
                playerHelpSection
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showsMetadataSettings) {
            MetadataSettingsSheet(
                language: model.language,
                provider: model.metadataProvider,
                initialAPIKey: model.metadataProvider == .tmdb
                    ? model.tmdbAPIKey
                    : model.omdbAPIKey,
                initialTranslationMode: model.overviewTranslationMode,
                save: { value, translationMode in
                    if model.metadataProvider == .tmdb {
                        model.tmdbAPIKey = value
                    } else {
                        model.omdbAPIKey = value
                    }
                    model.onMetadataAPIKeyChanged?(model.metadataProvider, value)
                    if model.overviewTranslationMode != translationMode {
                        model.overviewTranslationMode = translationMode
                        model.onOverviewTranslationModeChanged?(translationMode)
                    }
                    showsMetadataSettings = false
                },
                cancel: { showsMetadataSettings = false }
            )
        }
    }

    private var executableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                model.language == .russian ? "Исполняемый файл" : "Executable",
                systemImage: "terminal.fill"
            )
            .font(.headline)

            TextField(
                model.language == .russian ? "Путь к TorrServer" : "Path to TorrServer",
                text: Binding(
                    get: { model.path },
                    set: { value in
                        model.path = value
                        model.onPathChanged?(value)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .disabled(!model.canEditPath)

            HStack(spacing: 10) {
                GlassActionButton(
                    title: texts.choose,
                    systemImage: "folder",
                    isEnabled: model.canBrowse,
                    action: { model.onChoose?() }
                )

                GlassActionButton(
                    title: texts.downloadArm,
                    systemImage: "arrow.down.circle",
                    isEnabled: model.canDownload,
                    action: { model.onDownload?() }
                )
            }
        }
        .glassSection()
    }

    private var actionSection: some View {
        GeometryReader { geometry in
            let circleSize: CGFloat = 40
            let spacing: CGFloat = 10
            let buttonWidth = max(
                (geometry.size.width - circleSize - spacing * 2) / 2,
                120
            )

            HStack(spacing: spacing) {
                StartStopCircleButton(model: model, texts: texts)

                ServerActionCapsuleButton(
                    title: texts.webUI,
                    systemImage: "safari",
                    isEnabled: model.canOpenWeb,
                    action: { model.onOpenWeb?() }
                )
                .frame(width: buttonWidth, height: circleSize)

                diagnosticsButton
                    .frame(width: buttonWidth, height: circleSize)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 4)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                model.language == .russian ? "Настройки" : "Settings",
                systemImage: "switch.2"
            )
            .font(.headline)

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 0) {
                    GlassToggleRow(
                        title: texts.launchAtLogin,
                        systemImage: "person.crop.circle.badge.clock",
                        isOn: model.launchAtLogin,
                        onChange: { model.onLaunchAtLoginChanged?($0) }
                    )

                    GlassToggleRow(
                        title: texts.autoStartServer,
                        systemImage: "bolt.circle",
                        isOn: model.autoStartServer,
                        onChange: { model.onAutoStartChanged?($0) }
                    )

                    GlassToggleRow(
                        title: texts.showSpeed,
                        systemImage: "speedometer",
                        isOn: model.showSpeed,
                        onChange: { model.onShowSpeedChanged?($0) }
                    )

                    GlassToggleRow(
                        title: texts.hideDockIcon,
                        systemImage: "menubar.dock.rectangle",
                        isOn: model.hideDockIcon,
                        onChange: { model.onHideDockIconChanged?($0) }
                    )

                    GlassToggleRow(
                        title: texts.notifications,
                        systemImage: "bell.badge",
                        isOn: model.notificationsEnabled,
                        isEnabled: !model.notificationsAuthorizationPending,
                        onChange: { model.onNotificationsChanged?($0) }
                    )
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 145)

                VStack(spacing: 0) {
                    HStack {
                        Label(texts.speedFormat, systemImage: "speedometer")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        GlassSpeedUnitPicker(
                            unit: model.speedUnit,
                            automaticTitle: texts.automaticSpeed,
                            megabytesTitle: texts.megabytesSpeed,
                            megabitsTitle: texts.megabitsSpeed,
                            onChange: { model.onSpeedUnitChanged?($0) }
                        )
                    }
                    .frame(height: 29)

                    HStack {
                        Label(texts.languageLabel, systemImage: "globe")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        GlassLanguagePicker(
                            language: model.language,
                            russianTitle: texts.russian,
                            englishTitle: texts.english,
                            onChange: { model.onLanguageChanged?($0) }
                        )
                    }
                    .frame(height: 29)

                    HStack {
                        Label(texts.jackettSearch, systemImage: "magnifyingglass.circle")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        GlassJackettPicker(
                            isEnabled: model.jackettEnabled,
                            onChange: { model.onJackettEnabledChanged?($0) }
                        )
                    }
                    .frame(height: 29)

                    HStack {
                        Label(texts.metadataProvider, systemImage: "photo.on.rectangle.angled")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        GlassMetadataProviderPicker(
                            provider: model.metadataProvider,
                            onChange: { model.onMetadataProviderChanged?($0) }
                        )
                    }
                    .frame(height: 29)

                    HStack {
                        Label(texts.metadataAPIKey, systemImage: "key")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        Button {
                            showsMetadataSettings = true
                        } label: {
                            let apiKey = model.metadataProvider == .tmdb
                                ? model.tmdbAPIKey
                                : model.omdbAPIKey
                            Label(
                                apiKey.isEmpty
                                    ? texts.metadataConfigure
                                    : texts.metadataConfigured,
                                systemImage: apiKey.isEmpty
                                    ? "key"
                                    : "checkmark.circle.fill"
                            )
                            .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(height: 29)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .glassSection()
    }

    private var diagnosticsButton: some View {
        Button {
            showsDiagnostics.toggle()
        } label: {
            Label(
                model.language == .russian ? "Диагностика" : "Diagnostics",
                systemImage: "stethoscope"
            )
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .serverActionSurface()
        .help(model.latestDiagnostic.message)
        .popover(isPresented: $showsDiagnostics, arrowEdge: .bottom) {
            DiagnosticsPopover(model: model)
        }
    }

    private var playerHelpSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                Text(texts.playerHelpTitle)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(texts.playerHelpMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ForEach(model.detectedPlayers) { player in
                    PlayerStatusButton(
                        player: player,
                        isPreferred: model.preferredPlayer == player.choice,
                        language: model.language,
                        select: { model.onSelectPlayer?(player.choice) },
                        download: {
                            switch player.choice {
                            case .iina: model.onOpenIINADownload?()
                            case .vlc: model.onOpenVLCDownload?()
                            case .infuse: model.onOpenInfuseDownload?()
                            default: break
                            }
                        }
                    )
                }
            }
        }
        .serverBottomPanel()
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(
                        model.language == .russian ? "Хранилище" : "Storage",
                        systemImage: "internaldrive"
                    )
                    .font(.system(size: 12.5, weight: .semibold))

                    Spacer()

                    Button(role: .destructive) {
                        showsClearCacheConfirmation = true
                    } label: {
                        Label(
                            model.language == .russian ? "Очистить" : "Clear",
                            systemImage: "trash"
                        )
                    }
                    .controlSize(.small)
                    .disabled(model.isClearingCache || !model.canStop)
                    .popover(isPresented: $showsClearCacheConfirmation) {
                        clearCacheConfirmation
                    }

                    Button { model.onRefreshStorage?() } label: {
                        if model.isRefreshingStorage {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRefreshingStorage)
                }

                Text(texts.storageDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                storageValue(
                    title: model.language == .russian ? "Буфер TorrServer" : "TorrServer buffer",
                    value: storageUsageText
                )
                storageValue(
                    title: model.language == .russian ? "Кеш на диске" : "Disk cache",
                    value: model.storage.diskCacheEnabled
                        ? ByteCountFormatter.string(fromByteCount: model.storage.diskCacheSize, countStyle: .file)
                        : (model.language == .russian ? "Выключен" : "Disabled")
                )
                storageValue(
                    title: model.language == .russian ? "Свободно" : "Free space",
                    value: ByteCountFormatter.string(fromByteCount: model.storage.freeDiskSpace, countStyle: .file),
                    warning: model.storage.isLowOnDiskSpace
                )
            }
        }
        .serverBottomPanel()
    }

    private var clearCacheConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.language == .russian ? "Очистить кеш?" : "Clear cache?")
                .font(.headline)
            Text(model.language == .russian
                ? "Активные потоки будут остановлены. Материалы останутся в библиотеке."
                : "Active streams will stop. Library items will remain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(model.language == .russian ? "Отмена" : "Cancel") {
                    showsClearCacheConfirmation = false
                }
                Button(role: .destructive) {
                    showsClearCacheConfirmation = false
                    model.onClearCache?()
                } label: {
                    Text(model.language == .russian ? "Очистить" : "Clear")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func storageValue(title: String, value: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(warning ? Color.orange : Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var storageUsageText: String {
        let used = ByteCountFormatter.string(
            fromByteCount: model.storage.cacheUsed,
            countStyle: .memory
        )
        guard model.storage.cacheCapacity > 0 else { return used }
        let capacity = ByteCountFormatter.string(
            fromByteCount: model.storage.cacheCapacity,
            countStyle: .memory
        )
        return "\(used) / \(capacity)"
    }

    private func resultColor(_ kind: DiagnosticResultKind) -> Color {
        switch kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        default: return .secondary
        }
    }

    private func diagnosticResultIcon(
        _ kind: DiagnosticResultKind,
        fallback: String = "stethoscope"
    ) -> String {
        switch kind {
        case .checking: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        case .idle: return fallback
        }
    }
}

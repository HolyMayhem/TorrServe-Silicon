import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel
    @State private var showsClearCacheConfirmation = false
    @State private var scrollMetrics = AppScrollMetrics.zero
    @State private var scrollIndicatorIsVisible = false

    private var texts: Texts {
        Texts(language: model.language)
    }

    private var screenTitle: String {
        model.language == .russian ? "Настройки сервера" : "Server Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                title: screenTitle,
                message: model.language == .russian
                    ? "Управляйте сервером, исполняемым файлом, хранилищем и приложениями для воспроизведения."
                    : "Manage the server, executable, storage, and playback apps."
            )

            ScrollView {
                VStack(spacing: SettingsScreenLayout.sectionSpacing) {
                    serverOverviewSection
                    storageSection
                    ServerCacheSettingsSection(model: model)
                    executableSection
                    ServerDiagnosticsSection(model: model)
                    playerSection
                }
                .padding(.horizontal, SettingsScreenLayout.formContentInset)
                .padding(.top, SettingsScreenLayout.scrollContentTopPadding)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background {
                AppNativeScrollIndicatorHider()
            }
            .onScrollGeometryChange(for: AppScrollMetrics.self) { geometry in
                AppScrollMetrics(geometry)
            } action: { _, metrics in
                scrollMetrics = metrics
            }
            .onScrollPhaseChange { _, phase in
                withAnimation(.easeOut(duration: phase.isScrolling ? 0.08 : 0.24)) {
                    scrollIndicatorIsVisible = phase.isScrolling
                }
            }
            .overlay {
                AppScrollIndicator(
                    metrics: scrollMetrics,
                    topInset: 0,
                    bottomInset: 0,
                    isVisible: scrollIndicatorIsVisible
                )
            }
        }
        .frame(maxWidth: SettingsScreenLayout.contentMaxWidth)
        .padding(.horizontal, SettingsScreenLayout.horizontalPadding)
        .padding(.top, SettingsScreenLayout.topPadding)
        .padding(.bottom, SettingsScreenLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsVisualStyle.windowBackground)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var serverOverviewSection: some View {
        ServerSettingsGroup(title: "TorrServer") {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(model.effectiveStatusKind.color.opacity(0.14))
                    Image(systemName: serverStatusIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.effectiveStatusKind.color)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.language == .russian ? "Состояние" : "Status")
                        .font(.callout.weight(.medium))
                    Text(serverStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                serverPowerControl
            }
            .frame(minHeight: 54)

            if let activity = model.torrServerUpdateActivity {
                Divider()
                serverUpdateProgress(activity)
                    .padding(.vertical, 10)
            }

            Divider()

            HStack(spacing: 12) {
                Label(
                    model.language == .russian ? "Адрес" : "Address",
                    systemImage: "network"
                )
                .font(.callout)

                Spacer(minLength: 20)

                Text("localhost:8090")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    model.onOpenWeb?()
                } label: {
                    Label(texts.webUI, systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.canOpenWeb)
                .help(texts.openWebUI)
            }
            .frame(minHeight: 42)

            Divider()

            serverInfoRow(
                title: model.language == .russian ? "Версия" : "Version",
                value: model.torrServerVersion ?? "—",
                systemImage: "shippingbox"
            )
        }
        .help(
            model.serverConnectionIssue
                ?? (model.statusTooltip.isEmpty ? serverStatusDetail : model.statusTooltip)
        )
    }

    @ViewBuilder
    private var serverPowerControl: some View {
        if let activity = model.torrServerUpdateActivity {
            HStack(spacing: 6) {
                if activity.stage == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(
                        activity.clampedProgress.formatted(
                            .percent.precision(.fractionLength(0))
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .accessibilityLabel(activity.detail(language: model.language))
        } else if model.statusKind == .working {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(serverStatusDetail)
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
        } else {
            Button {
                model.canStop ? model.onStop?() : model.onStart?()
            } label: {
                Label(
                    model.canStop ? texts.stop : texts.start,
                    systemImage: model.canStop ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(model.canStop ? Color.red : Color.accentColor)
            .disabled(!(model.canStart || model.canStop))
            .help(model.canStop ? texts.stop : texts.start)
        }
    }

    private var executableSection: some View {
        ServerSettingsGroup(
            title: model.language == .russian ? "Исполняемый файл" : "Executable",
            footer: model.language == .russian
                ? "Файл программы TorrServer, который используется для запуска сервера."
                : "The TorrServer executable used to start the server."
        ) {
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
            .disabled(!model.canEditPath)
            .padding(.vertical, 11)

            Divider()

            HStack(spacing: 10) {
                if let update = model.torrServerUpdate {
                    Label(
                        model.language == .russian
                            ? "Доступна новая версия \(update.latestVersion)"
                            : "New version available: \(update.latestVersion)",
                        systemImage: "arrow.down.circle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(model.language == .russian
                        ? "Установлена \(update.installedVersion), доступна \(update.latestVersion)"
                        : "Installed \(update.installedVersion), available \(update.latestVersion)")
                }

                Spacer(minLength: 12)

                Button {
                    model.onChoose?()
                } label: {
                    Label(texts.choose, systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canBrowse)

                executableDownloadButton
            }
            .frame(minHeight: 50)
        }
    }

    private var storageSection: some View {
        ServerSettingsGroup(
            title: model.language == .russian ? "Хранилище" : "Storage",
            footer: texts.storageDescription
        ) {
            storageMetricRow(
                title: model.language == .russian ? "Буфер" : "Buffer",
                value: storageUsageText,
                systemImage: "memorychip"
            )
            Divider()
            storageMetricRow(
                title: model.language == .russian ? "Дисковый кеш" : "Disk cache",
                value: diskCacheText,
                systemImage: "externaldrive"
            )
            Divider()
            storageMetricRow(
                title: model.language == .russian ? "Свободное место" : "Available space",
                value: freeSpaceText,
                systemImage: "internaldrive",
                warning: model.storage.isLowOnDiskSpace
            )
            Divider()

            HStack(spacing: 8) {
                Button {
                    model.onRefreshStorage?()
                } label: {
                    if model.isRefreshingStorage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            model.language == .russian ? "Обновить" : "Refresh",
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isRefreshingStorage)
                .help(model.language == .russian ? "Обновить" : "Refresh")

                Spacer(minLength: 12)

                Button(role: .destructive) {
                    showsClearCacheConfirmation = true
                } label: {
                    Label(
                        model.language == .russian ? "Очистить кеш" : "Clear Cache",
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isClearingCache || !model.canStop)
                .popover(isPresented: $showsClearCacheConfirmation) {
                    clearCacheConfirmation
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var playerSection: some View {
        ServerSettingsGroup(title: texts.playerHelpTitle, footer: texts.playerHelpMessage) {
            ForEach(Array(model.detectedPlayers.enumerated()), id: \.element.id) { index, player in
                if index > 0 {
                    Divider()
                }
                playerRow(player)
            }
        }
    }

    private func playerRow(_ player: DetectedPlayer) -> some View {
        let isPreferred = model.preferredPlayer == player.choice

        return Button {
            if player.isInstalled {
                model.onSelectPlayer?(player.choice)
            } else {
                openDownload(for: player.choice)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playerIcon(for: player.choice))
                    .foregroundStyle(isPreferred ? Color.green : Color.secondary)
                    .frame(width: 18)

                Text(player.choice.title(language: model.language))
                    .font(.callout.weight(.medium))

                Spacer()

                Text(playerStatus(player, isPreferred: isPreferred))
                    .font(.caption)
                    .foregroundStyle(isPreferred ? Color.green : Color.secondary)

                Image(systemName: isPreferred
                    ? "checkmark.circle.fill"
                    : (player.isInstalled ? "chevron.right" : "arrow.down.circle"))
                    .foregroundStyle(isPreferred ? Color.green : Color.secondary)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func serverInfoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.callout)
            Spacer(minLength: 20)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 42)
    }

    private func serverUpdateProgress(_ activity: TorrServerUpdateActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: activity.stage == .completed
                    ? "checkmark.circle.fill"
                    : "arrow.down.circle.fill")
                    .foregroundStyle(activity.stage == .completed ? Color.green : Color.blue)
                Text(activity.detail(language: model.language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            TorrServerUpdateProgressBar(progress: activity.clampedProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var executableDownloadButton: some View {
        if let activity = model.torrServerUpdateActivity {
            Button {} label: {
                Label(
                    activity.kind == .update
                        ? (model.language == .russian ? "Обновление…" : "Updating…")
                        : texts.downloading,
                    systemImage: "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(true)
        } else if model.torrServerUpdate != nil {
            Button {
                model.onInstallTorrServerUpdate?()
            } label: {
                Label(
                    model.language == .russian ? "Обновить" : "Update",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        } else {
            Button {
                model.onDownload?()
            } label: {
                Label(texts.downloadArm, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canDownload)
        }
    }

    private func storageMetricRow(
        title: String,
        value: String,
        systemImage: String,
        warning: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.callout)
            Spacer(minLength: 20)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(warning ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 42)
    }

    private var serverStatusDetail: String {
        if model.serverConnectionIssue != nil {
            return model.language == .russian
                ? "Не удалось подключиться к TorrServer"
                : "Could not connect to TorrServer"
        }
        if !model.statusText.isEmpty {
            return model.statusText
        }
        switch model.statusKind {
        case .running:
            return model.language == .russian ? "Запущен" : "Running"
        case .working:
            return model.language == .russian ? "Выполняется операция…" : "Working…"
        case .failed:
            return model.language == .russian ? "Произошла ошибка" : "An error occurred"
        case .stopped:
            return model.language == .russian ? "Остановлен" : "Stopped"
        }
    }

    private var serverStatusIcon: String {
        switch model.effectiveStatusKind {
        case .running: return "checkmark"
        case .working: return "hourglass"
        case .failed: return "exclamationmark"
        case .stopped: return "power"
        }
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

    private var diskCacheText: String {
        model.storage.diskCacheEnabled
            ? ByteCountFormatter.string(
                fromByteCount: model.storage.diskCacheSize,
                countStyle: .file
            )
            : (model.language == .russian ? "Выключен" : "Disabled")
    }

    private var freeSpaceText: String {
        ByteCountFormatter.string(
            fromByteCount: model.storage.freeDiskSpace,
            countStyle: .file
        )
    }

    private func playerStatus(_ player: DetectedPlayer, isPreferred: Bool) -> String {
        if isPreferred {
            return model.language == .russian ? "По умолчанию" : "Default"
        }
        if player.isInstalled {
            return model.language == .russian ? "Установлен" : "Installed"
        }
        return model.language == .russian ? "Скачать" : "Download"
    }

    private func playerIcon(for choice: ExternalPlayerChoice) -> String {
        switch choice {
        case .iina: return "play.rectangle"
        case .vlc: return "play.circle"
        case .infuse: return "tv"
        case .quickTime: return "play.square"
        case .systemDefault: return "macwindow"
        case .custom: return "app.badge"
        }
    }

    private func openDownload(for choice: ExternalPlayerChoice) {
        switch choice {
        case .iina: model.onOpenIINADownload?()
        case .vlc: model.onOpenVLCDownload?()
        case .infuse: model.onOpenInfuseDownload?()
        default: break
        }
    }
}

struct ServerSettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .serverSettingsPanel()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
    }
}

extension View {
    func serverSettingsPanel() -> some View {
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

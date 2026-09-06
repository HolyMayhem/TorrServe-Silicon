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
        ScrollView {
            VStack(spacing: SettingsScreenLayout.sectionSpacing) {
                SettingsScreenTitle(title: screenTitle)

                SettingsIntroCard(
                    title: screenTitle,
                    message: model.language == .russian
                        ? "Управляйте сервером, исполняемым файлом, хранилищем и приложениями для воспроизведения."
                        : "Manage the server, executable, storage, and playback apps.",
                    systemImage: "network",
                    tint: .green
                )

                HStack(alignment: .top, spacing: 10) {
                    serverOverviewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    storageSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 128)

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
        .settingsScrollEdgeFade()
        .frame(maxWidth: SettingsScreenLayout.contentMaxWidth)
        .padding(.horizontal, SettingsScreenLayout.horizontalPadding)
        .padding(.top, SettingsScreenLayout.topPadding)
        .padding(.bottom, SettingsScreenLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var serverOverviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(model.effectiveStatusKind.color.opacity(0.14))
                    Image(systemName: serverStatusIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.effectiveStatusKind.color)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TorrServer")
                        .font(.headline)
                    Text(serverStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                serverPowerControl
            }

            Divider()

            if let activity = model.torrServerUpdateActivity {
                serverUpdateProgress(activity)
            } else {
                HStack(spacing: 12) {
                    serverInfo(
                        title: model.language == .russian ? "Адрес" : "Address",
                        value: "localhost:8090",
                        systemImage: "network"
                    )

                    serverInfo(
                        title: model.language == .russian ? "Версия" : "Version",
                        value: model.torrServerVersion ?? "—",
                        systemImage: "shippingbox"
                    )

                    Spacer(minLength: 4)

                    Button {
                        model.onOpenWeb?()
                    } label: {
                        Label(texts.webUI, systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canOpenWeb)
                    .help(texts.openWebUI)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .serverSettingsPanel()
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
        VStack(alignment: .leading, spacing: 9) {
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
            .disabled(!model.canEditPath)

            HStack(spacing: 8) {
                Text(model.language == .russian
                    ? "Файл программы TorrServer, который запускает сервер."
                    : "The TorrServer program file used to launch the server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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

                Spacer()

                Button {
                    model.onChoose?()
                } label: {
                    Label(texts.choose, systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canBrowse)

                executableDownloadButton
            }
        }
        .serverSettingsPanel()
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    model.language == .russian ? "Хранилище" : "Storage",
                    systemImage: "internaldrive"
                )
                .font(.headline)

                Spacer()

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

                Button {
                    model.onRefreshStorage?()
                } label: {
                    if model.isRefreshingStorage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshingStorage)
                .help(model.language == .russian ? "Обновить" : "Refresh")
            }

            Text(texts.storageDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 7) {
                storageMetric(
                    title: model.language == .russian ? "Буфер" : "Buffer",
                    value: storageUsageText
                )
                storageMetric(
                    title: model.language == .russian ? "Кеш" : "Cache",
                    value: diskCacheText
                )
                storageMetric(
                    title: model.language == .russian ? "Свободно" : "Available",
                    value: freeSpaceText,
                    warning: model.storage.isLowOnDiskSpace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .serverSettingsPanel()
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(texts.playerHelpTitle, systemImage: "play.rectangle.on.rectangle")
                .font(.headline)

            Text(texts.playerHelpMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(spacing: 5) {
                ForEach(model.detectedPlayers) { player in
                    playerRow(player)
                }
            }

            Spacer(minLength: 0)
        }
        .serverSettingsPanel()
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
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
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

    private func serverInfo(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
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

    private func storageMetric(title: String, value: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(warning ? Color.orange : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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

extension View {
    func serverSettingsPanel() -> some View {
        padding(14)
            .background(
                SettingsVisualStyle.panelBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

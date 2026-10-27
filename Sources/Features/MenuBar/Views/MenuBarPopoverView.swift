import AppKit
import SwiftUI

final class MenuBarPopoverModel: ObservableObject {
    @Published var language: AppLanguage = .systemDefault
    @Published var statusText = ""
    @Published var statusKind: MainStatusKind = .stopped
    @Published var isRunning = false
    @Published var canStart = false
    @Published var canStop = false
    @Published var canOpenWeb = true
    @Published var canDownload = true
    @Published var isDownloading = false
    @Published var isRestarting = false
    @Published var installedVersion: String?
    @Published var availableVersion: String?
    @Published var isCheckingForUpdate = false
    @Published var isInstallingUpdate = false
    @Published var activeTorrentCount: Int?
    @Published var cacheSnapshot: MenuBarCacheSnapshot?
    @Published var preferences = MenuBarPreferences.defaults

    @Published var speedText = ""
    @Published var speedSamples: [Double] = []
    @Published var activeTitle: String?
    @Published var materialIsActive = false
    @Published var activeSizeText = ""
    @Published var bufferProgress: Double?
    @Published var seeders = 0
    @Published var peers = 0
    @Published var isLoadingMaterial = false

    @Published var webUIAddress = ""
    @Published var qrImage: NSImage?
    @Published var showsQRCode = false

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenWeb: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRestart: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onShowUpdates: (() -> Void)?
    var onShowLibrary: (() -> Void)?
    var onQuit: (() -> Void)?
    var onQRCodeVisibilityChanged: (() -> Void)?
}

struct MenuBarPopoverView: View {
    @ObservedObject var model: MenuBarPopoverModel

    @State private var copiedAddress = false

    private var texts: Texts {
        Texts(language: model.language)
    }

    private var visibleSections: [MenuBarPopoverSection] {
        MenuBarPreferences.normalizedOrder(model.preferences.sectionOrder).filter { model.preferences.isVisible($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

            Divider()

            VStack(spacing: 0) {
                ForEach(visibleSections) { section in
                    popoverSection(section)
                        .padding(.vertical, section == .quickActions ? 15 : 14)

                    if section != visibleSections.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)

            if !visibleSections.isEmpty {
                Divider()
            }
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("TorrServer")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.statusKind.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(model.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if model.isRunning && model.preferences.showsSpeed {
                Text(model.speedText)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func popoverSection(_ section: MenuBarPopoverSection) -> some View {
        if model.preferences.isVisible(section) {
            switch section {
            case .serverVersion:
                versionSection
            case .serverAddress:
                addressSection
            case .activeTorrents:
                activeTorrentsSection
            case .cache:
                cacheSection
            case .restart:
                restartSection
            case .settings:
                navigationRow(
                    title: model.language == .russian ? "Настройки" : "Settings",
                    systemImage: "gearshape", action: { model.onShowSettings?() }
                )
            case .recentMaterial:
                currentMaterialCard
            case .speed:
                speedCard
            case .quickActions:
                actionButtons
            case .qrCode:
                webUICard
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.preferences.showsServerVersion {
                HStack {
                    Label("MatriX", systemImage: "shippingbox")
                    Spacer()
                    Text(model.installedVersion ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if model.preferences.showsUpdateStatus {
                Button { model.onShowUpdates?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.availableVersion == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        Text(updateStatusText)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.availableVersion == nil ? Color.secondary : Color.accentColor)
            }
        }
        .font(.system(size: 12))
    }

    private var updateStatusText: String {
        if model.isInstallingUpdate {
            return model.language == .russian ? "Установка обновления…" : "Installing update…"
        }
        if model.isCheckingForUpdate {
            return model.language == .russian ? "Проверка обновлений…" : "Checking for updates…"
        }
        if let version = model.availableVersion {
            return model.language == .russian ? "Доступно обновление: \(version)" : "Update available: \(version)"
        }
        return model.language == .russian ? "Проверить обновления" : "Check for updates"
    }

    private var addressSection: some View {
        HStack(spacing: 9) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            if model.preferences.showsServerAddress {
                Text(model.webUIAddress.isEmpty ? "—" : model.webUIAddress)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(model.webUIAddress)
            } else {
                Text(model.language == .russian ? "Скопировать адрес сервера" : "Copy server address")
                    .font(.system(size: 12))
            }
            Spacer(minLength: 4)
            if model.preferences.showsCopyAddress {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copiedAddress = pasteboard.setString(model.webUIAddress, forType: .string)
                } label: {
                    Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(model.webUIAddress.isEmpty)
                .accessibilityLabel(model.language == .russian ? "Скопировать адрес сервера" : "Copy server address")
                .help(copiedAddress
                    ? (model.language == .russian ? "Адрес скопирован" : "Address copied")
                    : (model.language == .russian ? "Скопировать адрес сервера" : "Copy server address"))
                .task(id: copiedAddress) {
                    guard copiedAddress else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    copiedAddress = false
                }
            }
        }
    }

    private var activeTorrentsSection: some View {
        navigationRow(
            title: model.language == .russian ? "Активные торренты" : "Active torrents",
            systemImage: "square.stack.3d.up",
            value: model.activeTorrentCount.map(String.init) ?? "—",
            action: { model.onShowLibrary?() }
        )
    }

    private var cacheSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label(model.language == .russian ? "Кэш" : "Cache", systemImage: "memorychip")
                Spacer()
                if !model.isRunning {
                    Text(model.language == .russian ? "Сервер остановлен" : "Server stopped")
                        .foregroundStyle(.secondary)
                } else if let cache = model.cacheSnapshot {
                    Text(cache.capacity > 0 ? cache.formattedUsage : (model.language == .russian ? "Пуст" : "Empty"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.language == .russian ? "Нет данных" : "Unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            if model.isRunning, let cache = model.cacheSnapshot, cache.capacity > 0 {
                ProgressView(value: cache.fraction)
                    .tint(.accentColor)
            }
        }
        .font(.system(size: 12))
        .help(model.language == .russian
            ? "Суммарный буфер активных торрентов. Это не объём памяти всего приложения."
            : "Combined buffers of active torrents, rather than total application memory.")
    }

    private var restartSection: some View {
        Button { model.onRestart?() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                Text(model.isRestarting
                    ? (model.language == .russian ? "Перезапуск…" : "Restarting…")
                    : (model.language == .russian ? "Перезапустить сервер" : "Restart server"))
                Spacer()
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isRunning || !model.canStop || model.isDownloading || model.isRestarting)
        .help(model.language == .russian
            ? "Перезапуск прервёт текущую трансляцию."
            : "Restarting interrupts the current stream.")
    }

    private func navigationRow(title: String, systemImage: String, value: String? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                Spacer()
                if let value { Text(value).monospacedDigit().foregroundStyle(.secondary) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentMaterialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    model.materialIsActive ? texts.currentMaterial : texts.recentMaterial,
                    systemImage: "film.stack"
                )
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                if model.isLoadingMaterial {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let title = model.activeTitle {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !model.activeSizeText.isEmpty {
                    Text(model.activeSizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let progress = model.bufferProgress {
                    VStack(spacing: 5) {
                        HStack {
                            Text(texts.buffer)
                            Spacer()
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: progress)
                            .tint(.green)
                    }
                }

                HStack(spacing: 8) {
                    statisticBadge(
                        title: texts.seeds,
                        value: model.seeders,
                        systemImage: "arrow.up.circle.fill"
                    )
                    statisticBadge(
                        title: texts.peers,
                        value: model.peers,
                        systemImage: "person.2.fill"
                    )
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                    Text(texts.noActiveMaterial)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(texts.speedHistory, systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(model.speedText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SpeedSparkline(samples: model.speedSamples)
                .frame(height: 58)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            PopoverActionButton(
                title: model.canStop ? (model.language == .russian ? "Стоп" : texts.stop) : texts.start,
                systemImage: model.canStop ? "stop.fill" : "play.fill",
                isEnabled: (model.canStop || model.canStart) && !model.isRestarting,
                action: {
                    if model.canStop {
                        model.onStop?()
                    } else {
                        model.onStart?()
                    }
                }
            )
            .accessibilityLabel(model.canStop ? texts.stop : texts.start)

            PopoverActionButton(
                title: texts.webUI,
                systemImage: "safari",
                isEnabled: model.canOpenWeb,
                action: { model.onOpenWeb?() }
            )

            PopoverActionButton(
                title: model.language == .russian ? "Окно" : "Window",
                systemImage: "macwindow",
                isEnabled: true,
                action: { model.onShowWindow?() }
            )
            .accessibilityLabel(texts.openWindow)
            .help(texts.openWindow)
        }
    }

    private var webUICard: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    model.showsQRCode.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    model.onQRCodeVisibilityChanged?()
                }
            } label: {
                HStack {
                    Label(
                        model.showsQRCode ? texts.hideQRCode : texts.showQRCode,
                        systemImage: "qrcode"
                    )
                    Spacer()
                    Image(systemName: model.showsQRCode ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if model.showsQRCode {
                Divider()

                VStack(spacing: 8) {
                    if let image = model.qrImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 154, height: 154)
                            .padding(8)
                            .background(Color.white, in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            ))
                    }

                    Text(texts.localWebUI)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.webUIAddress)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.onDownload?()
            } label: {
                Label(texts.downloadArm, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .disabled(!model.canDownload)

            Spacer()

            Button(model.language == .russian ? "Выйти" : texts.quit) {
                model.onQuit?()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statisticBadge(
        title: String,
        value: Int,
        systemImage: String
    ) -> some View {
        Label("\(title) \(value)", systemImage: systemImage)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

private struct SpeedSparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geometry in
            let values = samples.isEmpty ? [0, 0] : samples
            let maximum = max(values.max() ?? 0, 1)
            let points = values.enumerated().map { index, value in
                let denominator = CGFloat(max(values.count - 1, 1))
                return CGPoint(
                    x: CGFloat(index) / denominator * geometry.size.width,
                    y: geometry.size.height
                        - CGFloat(value / maximum) * (geometry.size.height - 6)
                        - 3
                )
            }

            ZStack {
                Path { path in
                    for row in 1...2 {
                        let y = geometry.size.height * CGFloat(row) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.12), style: StrokeStyle(
                    lineWidth: 0.5,
                    dash: [3, 4]
                ))

                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(
                            x: points[points.count - 1].x,
                            y: geometry.size.height
                        ))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.10),
                                Color.green.opacity(0.015)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityLabel("Download speed graph")
    }
}

private struct PopoverActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 17)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!isEnabled)
    }
}

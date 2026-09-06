import Foundation
import SwiftUI

struct AppSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @Binding var selection: AppSection?
    let isCompact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primarySections: [AppSection] {
        mainModel.jackettEnabled
            ? [.search, .library]
            : [.library]
    }

    var body: some View {
        Group {
            if isCompact {
                compactSidebar
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                expandedSidebar
                    .transition(.opacity)
            }
        }
        .backgroundPreferenceValue(SidebarSelectionBounds.self) { bounds in
            GeometryReader { geometry in
                if let selection, let anchor = bounds[selection] {
                    let frame = geometry[anchor]
                    SidebarSelectionGlass()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                            value: frame
                        )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.16), value: isCompact)
        .onMoveCommand { direction in
            let sections = primarySections + [.settings, .server]
            guard let selection, let index = sections.firstIndex(of: selection) else { return }
            switch direction {
            case .up: self.selection = sections[max(index - 1, 0)]
            case .down: self.selection = sections[min(index + 1, sections.count - 1)]
            default: break
            }
        }
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            Text("TorrServe")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(primarySections) { section in
                        navigationButton(section)
                    }

                    Text(mainModel.language == .russian ? "Настройки" : "Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    navigationButton(.settings)
                    navigationButton(.server)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            if let update = mainModel.torrServerUpdate {
                SidebarUpdateNotice(
                    update: update,
                    language: mainModel.language
                ) {
                    selection = .server
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider()

            ServerStatusSidebarView(
                mainModel: mainModel,
                materialCount: libraryModel.torrents.count
            )
            .padding(14)
        }
    }

    private func navigationButton(_ section: AppSection) -> some View {
        Button {
            selection = section
        } label: {
            SidebarNavigationItem(section: section, language: mainModel.language)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .foregroundStyle(selection == section ? Color.accentColor : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .anchorPreference(key: SidebarSelectionBounds.self, value: .bounds) {
            [section: $0]
        }
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var compactSidebar: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 66)
                .accessibilityHidden(true)

            VStack(spacing: 9) {
                ForEach(primarySections) { section in
                    CompactSidebarButton(
                        section: section,
                        language: mainModel.language,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }

                Divider()
                    .frame(width: 34)
                    .padding(.vertical, 7)

                CompactSidebarButton(
                    section: .settings,
                    language: mainModel.language,
                    isSelected: selection == .settings
                ) {
                    selection = .settings
                }

                CompactSidebarButton(
                    section: .server,
                    language: mainModel.language,
                    isSelected: selection == .server
                ) {
                    selection = .server
                }
            }

            Spacer(minLength: 12)

            if let update = mainModel.torrServerUpdate {
                Button {
                    selection = .server
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help(mainModel.language == .russian
                    ? "Доступна новая версия \(update.latestVersion)"
                    : "New version available: \(update.latestVersion)")
                .accessibilityLabel(mainModel.language == .russian
                    ? "Доступна новая версия \(update.latestVersion)"
                    : "New version available: \(update.latestVersion)")
                .padding(.bottom, 8)
            }

            Divider()

            CompactServerStatusView(mainModel: mainModel)
                .padding(.vertical, 14)
        }
    }
}

private struct SidebarUpdateNotice: View {
    let update: TorrServerAvailableUpdate
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(language == .russian ? "Доступно обновление" : "Update available")
                        .font(.caption.weight(.semibold))
                    Text(update.latestVersion)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.14), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language == .russian
            ? "Установлена \(update.installedVersion), доступна \(update.latestVersion)"
            : "Installed \(update.installedVersion), available \(update.latestVersion)")
    }
}

private struct CompactSidebarButton: View {
    let section: AppSection
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: section.systemImage)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 48, height: 48)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .anchorPreference(key: SidebarSelectionBounds.self, value: .bounds) {
            [section: $0]
        }
        .help(section.sidebarTitle(language: language))
        .accessibilityLabel(section.sidebarTitle(language: language))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CompactServerStatusView: View {
    @ObservedObject var mainModel: MainWindowModel

    private var texts: Texts { Texts(language: mainModel.language) }

    var body: some View {
        Button {
            mainModel.canStop ? mainModel.onStop?() : mainModel.onStart?()
        } label: {
            ZStack {
                Circle()
                    .fill(mainModel.effectiveStatusKind.color.opacity(0.12))
                Circle()
                    .stroke(mainModel.effectiveStatusKind.color.opacity(0.42), lineWidth: 1)

                if let activity = mainModel.torrServerUpdateActivity {
                    if activity.stage == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        ProgressView(value: activity.clampedProgress)
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(.blue)
                    }
                } else if mainModel.statusKind == .working {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: mainModel.canStop ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mainModel.effectiveStatusKind.color)
                }
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(
            mainModel.torrServerUpdateActivity != nil
                || !(mainModel.canStart || mainModel.canStop)
        )
        .help(
            mainModel.torrServerUpdateActivity?.detail(language: mainModel.language)
                ?? mainModel.serverConnectionIssue
                ?? (mainModel.canStop ? texts.stop : texts.start)
        )
        .accessibilityLabel(mainModel.canStop ? texts.stop : texts.start)
    }
}

struct SidebarNavigationItem: View {
    let section: AppSection
    let language: AppLanguage

    private var displayTitle: String {
        guard language == .russian else {
            return section.sidebarTitle(language: language)
        }

        switch section {
        case .settings:
            return "Общие\nнастройки"
        case .server:
            return "Настройки\nсервера"
        case .library, .search:
            return section.sidebarTitle(language: language)
        }
    }

    private var rowHeight: CGFloat {
        language == .russian && (section == .settings || section == .server)
            ? 52
            : 40
    }

    var body: some View {
        Label {
            Text(displayTitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: section.systemImage)
        }
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .imageScale(.large)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(section.sidebarTitle(language: language))
    }
}

private struct SidebarSelectionBounds: PreferenceKey {
    static let defaultValue: [AppSection: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AppSection: Anchor<CGRect>],
        nextValue: () -> [AppSection: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct SidebarSelectionGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

    var body: some View {
        surface
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            }
            .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else if #available(macOS 26.0, *) {
            Color.clear
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: shape
                )
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.08)), in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay(shape.fill(Color.accentColor.opacity(0.06)))
        }
    }
}

struct ServerStatusSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    let materialCount: Int

    private var texts: Texts { Texts(language: mainModel.language) }

    private var cacheText: String {
        ByteCountFormatter.string(
            fromByteCount: mainModel.storage.cacheUsed,
            countStyle: .memory
        )
    }

    private var speedText: String {
        guard mainModel.canStop else {
            return SpeedFormatter.string(bytesPerSecond: 0, unit: mainModel.speedUnit)
        }
        return mainModel.currentSpeedText.isEmpty
            ? SpeedFormatter.string(bytesPerSecond: 0, unit: mainModel.speedUnit)
            : mainModel.currentSpeedText
    }

    private var cacheTitle: String {
        mainModel.language == .russian ? "Кеш" : "Cache"
    }

    private var speedHelp: String {
        mainModel.language == .russian
            ? "Текущая скорость загрузки"
            : "Current download speed"
    }

    private var materialsHelp: String {
        mainModel.language == .russian
            ? "Материалов на сервере: \(materialCount)"
            : "Materials on the server: \(materialCount)"
    }

    private var statusTitle: String {
        if let activity = mainModel.torrServerUpdateActivity {
            return activity.title(language: mainModel.language)
        }
        if mainModel.serverConnectionIssue != nil {
            return mainModel.language == .russian ? "Нет подключения" : "No connection"
        }
        switch mainModel.statusKind {
        case .running:
            return mainModel.language == .russian ? "Запущен" : "Running"
        case .working:
            return mainModel.language == .russian ? "Запускается" : "Working"
        case .failed:
            return mainModel.language == .russian ? "Ошибка" : "Error"
        case .stopped:
            return mainModel.language == .russian ? "Остановлен" : "Stopped"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(mainModel.effectiveStatusKind.color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TorrServer")
                        .font(.subheadline.weight(.semibold))
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    mainModel.canStop ? mainModel.onStop?() : mainModel.onStart?()
                } label: {
                    if let activity = mainModel.torrServerUpdateActivity {
                        if activity.stage == .completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                                .frame(width: 30, height: 30)
                        } else {
                            ProgressView(value: activity.clampedProgress)
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(.blue)
                                .frame(width: 30, height: 30)
                        }
                    } else if mainModel.statusKind == .working {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: mainModel.canStop ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(mainModel.effectiveStatusKind.color)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(mainModel.effectiveStatusKind.color.opacity(0.35), lineWidth: 1)
                }
                .contentShape(Circle())
                .disabled(
                    mainModel.torrServerUpdateActivity != nil
                        || !(mainModel.canStart || mainModel.canStop)
                )
                .help(
                    mainModel.torrServerUpdateActivity?.detail(language: mainModel.language)
                        ?? (mainModel.canStop ? texts.stop : texts.start)
                )
                .accessibilityLabel(mainModel.canStop ? texts.stop : texts.start)
            }

            if let activity = mainModel.torrServerUpdateActivity {
                VStack(alignment: .leading, spacing: 7) {
                    Text(activity.detail(language: mainModel.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    TorrServerUpdateProgressBar(progress: activity.clampedProgress)
                }
            } else {
                HStack(spacing: 10) {
                    compactMetric(
                        value: speedText,
                        systemImage: "arrow.down",
                        help: speedHelp
                    )

                    Divider()
                        .frame(height: 14)

                    compactMetric(
                        value: materialCount.formatted(),
                        systemImage: "film.stack",
                        help: materialsHelp
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)

                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text(cacheTitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(cacheText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .help(mainModel.serverConnectionIssue ?? statusTitle)
    }

    private func compactMetric(
        value: String,
        systemImage: String,
        help: String
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .combine)
        .help(help)
    }
}

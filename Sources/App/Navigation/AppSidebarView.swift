import AppKit
import SwiftUI

struct AppSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @Binding var selection: AppSection?

    private var primarySections: [AppSection] {
        var sections: [AppSection] = mainModel.jackettEnabled ? [.search, .library] : [.library]
        if mainModel.showsOfflineSection { sections.append(.offline) }
        return sections
    }

    var body: some View {
        expandedSidebar
        .background(SettingsVisualStyle.sidebarBackground)
        .onMoveCommand { direction in
            let sections = primarySections
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
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(primarySections) { section in
                        navigationButton(section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            if let update = mainModel.torrServerUpdate {
                SidebarUpdateNotice(
                    update: update,
                    language: mainModel.language,
                    canInstall: mainModel.canInstallTorrServerUpdate,
                    showDetails: { mainModel.onOpenSettings?(.updates) },
                    install: { mainModel.onInstallTorrServerUpdate?() }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            expandedSettingsButton
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

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
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: selection == section))
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var expandedSettingsButton: some View {
        Button {
            mainModel.onOpenSettings?(.general)
        } label: {
            Label(
                mainModel.language == .russian ? "Настройки" : "Settings",
                systemImage: "gearshape"
            )
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .imageScale(.large)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle())
        .help(mainModel.language == .russian ? "Открыть настройки" : "Open Settings")
    }

}

struct SidebarUpdateNotice: View {
    let update: TorrServerAvailableUpdate
    let language: AppLanguage
    let canInstall: Bool
    let showDetails: () -> Void
    let install: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: showDetails) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language == .russian ? "Обновление MatriX" : "MatriX update")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.7) : Color.secondary)
                    Text(update.latestVersion)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(language == .russian ? "Сведения об обновлении" : "Update details")

            Button(action: install) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.07), in: Circle())
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canInstall)
            .opacity(canInstall ? 1 : 0.45)
            .help(language == .russian ? "Установить \(update.latestVersion)" : "Install \(update.latestVersion)")
            .accessibilityLabel(language == .russian ? "Установить обновление TorrServer" : "Install TorrServer update")
        }
        .padding(10)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct SidebarNavigationItem: View {
    let section: AppSection
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 24)
            Text(section.sidebarTitle(language: language))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
            .font(.system(size: 16, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(section.sidebarTitle(language: language))
    }
}

/// Flat sidebar rows deliberately avoid Liquid Glass, including on macOS 26.
private struct SidebarRowButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        SidebarRowButton(
            label: configuration.label,
            isSelected: isSelected,
            isPressed: configuration.isPressed
        )
    }
}

private struct SidebarRowButton<Label: View>: View {
    let label: Label
    let isSelected: Bool
    let isPressed: Bool
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isActive: Bool { controlActiveState != .inactive }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: isActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
        }
        return Color.primary.opacity(isPressed ? 0.12 : (isHovered ? 0.06 : 0))
    }

    var body: some View {
        label
            .foregroundStyle(isSelected && isActive
                ? Color(nsColor: .alternateSelectedControlTextColor)
                : Color.primary)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

struct ServerStatusSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    let materialCount: Int

    private var texts: Texts { Texts(language: mainModel.language) }

    private var speedText: String {
        guard mainModel.canStop else {
            return SpeedFormatter.string(bytesPerSecond: 0, unit: mainModel.speedUnit)
        }
        return mainModel.currentSpeedText.isEmpty
            ? SpeedFormatter.string(bytesPerSecond: 0, unit: mainModel.speedUnit)
            : mainModel.currentSpeedText
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
                .buttonStyle(.borderless)
                .background(Color.primary.opacity(0.06), in: Circle())
                .tint(mainModel.effectiveStatusKind.color)
                .foregroundStyle(mainModel.effectiveStatusKind.color)
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
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
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

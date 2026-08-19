import Foundation
import SwiftUI

struct AppSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @Binding var selection: AppSection?
    let isCompact: Bool

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
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.16), value: isCompact)
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

            List(selection: $selection) {
                Section {
                    ForEach(primarySections) { section in
                        SidebarNavigationItem(
                            section: section,
                            language: mainModel.language
                        )
                    }
                }

                Section(mainModel.language == .russian ? "Настройки" : "Settings") {
                    SidebarNavigationItem(
                        section: .settings,
                        language: mainModel.language
                    )

                    SidebarNavigationItem(
                        section: .server,
                        language: mainModel.language
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            ServerStatusSidebarView(
                mainModel: mainModel,
                materialCount: libraryModel.torrents.count
            )
            .padding(14)
        }
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

            Divider()

            CompactServerStatusView(mainModel: mainModel)
                .padding(.vertical, 14)
        }
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
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
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

                if mainModel.statusKind == .working {
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
        .disabled(!(mainModel.canStart || mainModel.canStop))
        .help(mainModel.serverConnectionIssue ?? (mainModel.canStop ? texts.stop : texts.start))
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
            .tag(section)
            .accessibilityLabel(section.sidebarTitle(language: language))
            .listRowInsets(
                EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
            )
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
                    if mainModel.statusKind == .working {
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
                .disabled(!(mainModel.canStart || mainModel.canStop))
                .help(mainModel.canStop ? texts.stop : texts.start)
                .accessibilityLabel(mainModel.canStop ? texts.stop : texts.start)
            }

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

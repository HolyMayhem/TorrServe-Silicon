import Foundation
import SwiftUI

struct AppSidebarView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var libraryModel: LibraryViewModel
    @Binding var selection: AppSection?

    private var primarySections: [AppSection] {
        mainModel.jackettEnabled
            ? [.search, .library]
            : [.library]
    }

    var body: some View {
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
        .background(.thinMaterial)
    }
}

struct SidebarNavigationItem: View {
    let section: AppSection
    let language: AppLanguage

    var body: some View {
        Label(section.sidebarTitle(language: language), systemImage: section.systemImage)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .imageScale(.large)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
                    .fill(mainModel.statusKind.color)
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
                .foregroundStyle(mainModel.statusKind.color)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(mainModel.statusKind.color.opacity(0.35), lineWidth: 1)
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

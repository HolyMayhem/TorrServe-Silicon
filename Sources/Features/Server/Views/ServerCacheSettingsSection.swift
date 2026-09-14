import SwiftUI

struct ServerCacheSettingsSection: View {
    @ObservedObject var model: MainWindowModel

    private var isRussian: Bool { model.language == .russian }
    private var isBusy: Bool {
        model.isLoadingServerSettings || model.isSavingServerSettings
    }

    var body: some View {
        ServerSettingsGroup(title: isRussian ? "Настройки кеша" : "Cache Settings") {
            cacheControls
                .disabled(!model.hasLoadedServerSettings || isBusy)
            Divider()
            storageControls
                .disabled(!model.hasLoadedServerSettings || isBusy)
            Divider()
            footer
        }
    }

    private var cacheControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingSlider(
                title: isRussian ? "Размер кеша" : "Cache size",
                value: cacheSizeBinding,
                range: 16...4_096,
                step: 16,
                valueText: "\(model.serverSettingsDraft.cacheSizeMB) MB"
            )

            cacheAllocationBar

            Divider()

            settingSlider(
                title: isRussian ? "Опережающий кеш" : "Read-ahead cache",
                value: readAheadBinding,
                range: 5...100,
                step: 1,
                valueText: "\(model.serverSettingsDraft.readerReadAhead)%"
            )

            Divider()

            settingSlider(
                title: isRussian ? "Буфер предзагрузки" : "Preload buffer",
                value: preloadBinding,
                range: 0...100,
                step: 1,
                valueText: "\(model.serverSettingsDraft.preloadCache)% · \(model.serverSettingsDraft.preloadSizeMB) MB"
            )
        }
    }

    private var cacheAllocationBar: some View {
        HStack(spacing: 6) {
            Text(isRussian
                ? "Позади \(model.serverSettingsDraft.trailingCachePercent)%"
                : "Behind \(model.serverSettingsDraft.trailingCachePercent)%")
            Text("·")
            Text(isRussian
                ? "Впереди \(model.serverSettingsDraft.readerReadAhead)%"
                : "Ahead \(model.serverSettingsDraft.readerReadAhead)%")
            Text("·")
            Text(isRussian
                ? "Предзагрузка \(model.serverSettingsDraft.preloadCache)%"
                : "Preload \(model.serverSettingsDraft.preloadCache)%")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    private var storageControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRussian ? "Место хранения" : "Cache storage")
                        .font(.callout.weight(.medium))
                    Text(isRussian
                        ? "Оперативная память работает быстрее; диск сохраняет кеш между операциями."
                        : "Memory is faster; disk keeps cached data between operations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: model.serverSettingsDraft.useDisk
                    ? "externaldrive.fill"
                    : "memorychip.fill")
                    .foregroundStyle(Color.blue)
                    .contentTransition(.symbolEffect(.replace))

                Text(model.serverSettingsDraft.useDisk
                    ? (isRussian ? "Диск" : "Disk")
                    : (isRussian ? "Память" : "Memory"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("", isOn: useDiskBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(minHeight: 56)
            .animation(.easeInOut(duration: 0.18), value: model.serverSettingsDraft.useDisk)

            if model.serverSettingsDraft.useDisk {
                Divider()

                HStack(spacing: 12) {
                    Text(isRussian ? "Папка кеша" : "Cache folder")
                        .font(.callout)

                    Spacer(minLength: 20)

                    TextField(
                        isRussian ? "Выберите папку" : "Choose a folder",
                        text: Binding(
                            get: { model.serverSettingsDraft.torrentsSavePath },
                            set: {
                                model.serverSettingsDraft.torrentsSavePath = $0
                                model.serverSettingsResult = .idle
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 310)

                    Button {
                        model.onChooseServerCacheFolder?()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help(isRussian ? "Выбрать папку кеша" : "Choose cache folder")
                }
                .frame(minHeight: 46)

                Divider()

                Toggle(
                    isRussian
                        ? "Удалять кеш при удалении материала"
                        : "Remove cache when an item is dropped",
                    isOn: Binding(
                        get: { model.serverSettingsDraft.removeCacheOnDrop },
                        set: {
                            model.serverSettingsDraft.removeCacheOnDrop = $0
                            model.serverSettingsResult = .idle
                        }
                    )
                )
                .toggleStyle(.switch)
                .frame(minHeight: 42)
            } else {
                Divider()

                Label(
                    isRussian
                        ? "Кеш хранится только в оперативной памяти."
                        : "Cache is kept in memory only.",
                    systemImage: "memorychip"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                settingsResult

                if model.hasUnsavedServerSettings,
                   model.serverSettingsResult.kind == .idle {
                    Label(
                        isRussian
                            ? "Сохраните настройки, чтобы применить изменения."
                            : "Save settings to apply your changes.",
                        systemImage: "circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(
                .easeInOut(duration: 0.18),
                value: model.hasUnsavedServerSettings
            )

            if model.isLoadingServerSettings {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    model.onLoadServerSettings?()
                } label: {
                    Label(
                        isRussian ? "Обновить" : "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || model.statusKind != .running)
                .help(isRussian ? "Обновить настройки" : "Refresh settings")
            }

            Spacer()

            Button(isRussian ? "По умолчанию" : "Defaults") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.serverSettingsDraft = .defaults
                    model.serverSettingsResult = .idle
                }
            }
            .disabled(!model.hasLoadedServerSettings || isBusy)

            Button {
                model.onSaveServerSettings?()
            } label: {
                if model.isSavingServerSettings {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(isRussian ? "Сохранить" : "Save")
                }
            }
            .liquidGlassProminentControl()
            .disabled(
                !model.hasLoadedServerSettings
                    || !model.hasUnsavedServerSettings
                    || isBusy
            )
            .keyboardShortcut("s", modifiers: [.command])
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var settingsResult: some View {
        switch model.serverSettingsResult.kind {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(isRussian ? "Обновление…" : "Updating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success, .warning, .failure:
            Label(
                model.serverSettingsResult.message,
                systemImage: resultIcon
            )
            .font(.caption)
            .foregroundStyle(resultColor)
            .lineLimit(2)
        }
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 10)
    }

    private var cacheSizeBinding: Binding<Double> {
        Binding(
            get: { Double(model.serverSettingsDraft.cacheSizeMB) },
            set: {
                model.serverSettingsDraft.cacheSizeMB = Int($0)
                model.serverSettingsResult = .idle
            }
        )
    }

    private var readAheadBinding: Binding<Double> {
        Binding(
            get: { Double(model.serverSettingsDraft.readerReadAhead) },
            set: {
                model.serverSettingsDraft.readerReadAhead = Int($0)
                model.serverSettingsResult = .idle
            }
        )
    }

    private var preloadBinding: Binding<Double> {
        Binding(
            get: { Double(model.serverSettingsDraft.preloadCache) },
            set: {
                model.serverSettingsDraft.preloadCache = Int($0)
                model.serverSettingsResult = .idle
            }
        )
    }

    private var useDiskBinding: Binding<Bool> {
        Binding(
            get: { model.serverSettingsDraft.useDisk },
            set: {
                model.serverSettingsDraft.useDisk = $0
                model.serverSettingsResult = .idle
            }
        )
    }

    private var resultIcon: String {
        switch model.serverSettingsResult.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        case .idle, .checking: return "circle"
        }
    }

    private var resultColor: Color {
        switch model.serverSettingsResult.kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        case .idle, .checking: return .secondary
        }
    }
}

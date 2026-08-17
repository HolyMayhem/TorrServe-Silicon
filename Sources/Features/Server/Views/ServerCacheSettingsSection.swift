import SwiftUI

struct ServerCacheSettingsSection: View {
    @ObservedObject var model: MainWindowModel

    private var isRussian: Bool { model.language == .russian }
    private var isBusy: Bool {
        model.isLoadingServerSettings || model.isSavingServerSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 20) {
                cacheControls
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                storageControls
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .disabled(!model.hasLoadedServerSettings || isBusy)

            Divider()

            footer
        }
        .serverSettingsPanel()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(
                isRussian ? "Настройки кеша" : "Cache Settings",
                systemImage: "memorychip"
            )
            .font(.headline)

            Spacer()

            if model.isLoadingServerSettings {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.onLoadServerSettings?()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy || model.statusKind != .running)
            .help(isRussian ? "Обновить настройки" : "Refresh settings")
        }
    }

    private var cacheControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            settingSlider(
                title: isRussian ? "Размер кеша" : "Cache size",
                value: cacheSizeBinding,
                range: 16...4_096,
                step: 16,
                valueText: "\(model.serverSettingsDraft.cacheSizeMB) MB"
            )

            cacheAllocationBar

            settingSlider(
                title: isRussian ? "Опережающий кеш" : "Read-ahead cache",
                value: readAheadBinding,
                range: 5...100,
                step: 1,
                valueText: "\(model.serverSettingsDraft.readerReadAhead)%"
            )

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
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                let trailingWidth = geometry.size.width
                    * CGFloat(model.serverSettingsDraft.trailingCachePercent) / 100
                let preloadWidth = geometry.size.width
                    * CGFloat(model.serverSettingsDraft.preloadCache) / 100

                VStack(spacing: 3) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.green.opacity(0.92))

                        Color.blue.opacity(0.88)
                            .frame(width: trailingWidth)

                        Rectangle()
                            .fill(Color.primary.opacity(0.72))
                            .frame(width: 1)
                            .offset(x: trailingWidth)
                    }
                    .clipShape(Capsule())

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))

                        Capsule()
                            .fill(Color.orange.opacity(0.95))
                            .frame(width: preloadWidth)
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: trailingWidth)
                .animation(.easeInOut(duration: 0.16), value: preloadWidth)
            }
            .frame(height: 13)

            HStack(spacing: 12) {
                allocationLegend(
                    color: .blue,
                    text: isRussian
                        ? "Позади \(model.serverSettingsDraft.trailingCachePercent)%"
                        : "Behind \(model.serverSettingsDraft.trailingCachePercent)%"
                )
                allocationLegend(
                    color: .green,
                    text: isRussian
                        ? "Впереди \(model.serverSettingsDraft.readerReadAhead)%"
                        : "Ahead \(model.serverSettingsDraft.readerReadAhead)%"
                )
                allocationLegend(
                    color: .orange,
                    text: isRussian
                        ? "Предзагрузка \(model.serverSettingsDraft.preloadCache)%"
                        : "Preload \(model.serverSettingsDraft.preloadCache)%"
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var storageControls: some View {
        VStack(alignment: .leading, spacing: 13) {
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

                HStack(spacing: 9) {
                    Image(systemName: model.serverSettingsDraft.useDisk
                        ? "externaldrive.fill"
                        : "memorychip.fill")
                        .foregroundStyle(Color.blue)
                        .contentTransition(.symbolEffect(.replace))

                    Text(model.serverSettingsDraft.useDisk
                        ? (isRussian ? "Диск" : "Disk")
                        : (isRussian ? "Память" : "Memory"))
                        .font(.callout.weight(.medium))
                        .frame(minWidth: 58, alignment: .leading)

                    Toggle("", isOn: useDiskBinding)
                        .labelsHidden()
                        .toggleStyle(LiquidGlassToggleStyle(width: 46, height: 26))
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 36)
                .liquidGlassPanel(cornerRadius: 18, interactive: true)
                .animation(
                    .easeInOut(duration: 0.18),
                    value: model.serverSettingsDraft.useDisk
                )
            }

            if model.serverSettingsDraft.useDisk {
                VStack(alignment: .leading, spacing: 7) {
                    Text(isRussian ? "Папка кеша" : "Cache folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
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

                        Button {
                            model.onChooseServerCacheFolder?()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .liquidGlassControl()
                        .help(isRussian ? "Выбрать папку кеша" : "Choose cache folder")
                    }

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
                    .toggleStyle(LiquidGlassToggleStyle())
                }
            } else {
                Label(
                    isRussian
                        ? "Кеш хранится только в оперативной памяти."
                        : "Cache is kept in memory only.",
                    systemImage: "memorychip"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
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
    }

    private func allocationLegend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

import SwiftUI

struct MatrixDowngradeSettingsView: View {
    @ObservedObject var model: MainWindowModel
    @State private var selectedTag: String?
    @State private var pendingRelease: TorrServerDowngradeRelease?
    @State private var showsConfirmation = false
    private var isRussian: Bool { model.language == .russian }
    private var isBusy: Bool {
        model.isLoadingOlderMatrixReleases || model.torrServerUpdateActivity != nil || model.statusKind == .working
    }
    private var selectedRelease: TorrServerDowngradeRelease? {
        model.olderMatrixReleases.first { $0.tagName == selectedTag }
    }

    var body: some View {
        ServerSettingsGroup(
            title: isRussian ? "Даунгрейд MatriX" : "Downgrade MatriX",
            footer: isRussian
                ? "Для проверки обычного обновления. Загружается официальный старый релиз для Apple Silicon; предыдущий исполняемый файл сохраняется."
                : "Test the normal update flow using an official older Apple Silicon release. The previous executable is retained."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isRussian ? "Текущая версия" : "Current version")
                    Spacer()
                    Text(model.torrServerVersion ?? "—")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack {
                    Button(isRussian ? "Найти старые версии" : "Find older versions") {
                        model.onLoadOlderMatrixReleases?()
                    }
                    .disabled(isBusy)
                    if model.isLoadingOlderMatrixReleases { ProgressView().controlSize(.small) }
                }
                if !model.olderMatrixReleases.isEmpty {
                    Picker(isRussian ? "Старая версия MatriX" : "Older MatriX version", selection: $selectedTag) {
                        ForEach(model.olderMatrixReleases) { release in
                            Text(release.version).tag(Optional(release.tagName))
                        }
                    }
                    .disabled(isBusy)
                    Button(isRussian ? "Выполнить даунгрейд…" : "Downgrade…", role: .destructive) {
                        pendingRelease = selectedRelease
                        showsConfirmation = true
                    }
                    .disabled(isBusy || selectedRelease == nil)
                }
                if let activity = model.torrServerUpdateActivity, activity.kind == .downgrade {
                    Text(activity.detail(language: model.language))
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: activity.clampedProgress)
                }
                if let message = model.matrixDowngradeMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 12)
            .searchableSetting(isRussian ? "Старая версия MatriX" : "Older MatriX version")

            if model.matrixDowngradeTestActive {
                Divider()
                MatrixUpdateTestStatusView(model: model)
            }
        }
        .onChange(of: model.olderMatrixReleases, initial: true) { _, releases in
            if !releases.contains(where: { $0.tagName == selectedTag }) {
                selectedTag = releases.first?.tagName
            }
        }
        .confirmationDialog(
            isRussian ? "Выполнить даунгрейд MatriX?" : "Downgrade MatriX?",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            if let release = pendingRelease {
                Button(isRussian ? "Установить \(release.version)" : "Install \(release.version)", role: .destructive) {
                    model.onDowngradeMatrix?(release)
                }
            }
            Button(isRussian ? "Отмена" : "Cancel", role: .cancel) {}
        } message: {
            Text(isRussian
                ? "Работающий сервер будет перезапущен, воспроизведение прервётся. Старая версия использует текущие данные сервера. При неудачном запуске приложение вернёт предыдущий исполняемый файл. Автоустановка обновлений приостановится до ручного обновления, возобновления или перезапуска приложения."
                : "A running server will restart and playback will be interrupted. The older version uses the current server data. If startup fails, the app restores the previous executable. Automatic updates pause until a manual update, resuming, or app restart.")
        }
    }
}

struct MatrixUpdateTestStatusView: View {
    @ObservedObject var model: MainWindowModel
    private var isRussian: Bool { model.language == .russian }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isRussian
                ? "Режим проверки обновления: автоустановка временно приостановлена. Проверка новых версий и ручное обновление работают."
                : "Update test mode: automatic installation is temporarily paused. Update discovery and manual updates remain available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(isRussian ? "Открыть обновления" : "Open Updates") {
                    model.onOpenSettings?(.updates)
                }
                Button(isRussian ? "Завершить проверку" : "End test mode") {
                    model.onResumeMatrixUpdates?()
                }
                .disabled(model.torrServerUpdateActivity != nil)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 12)
        .searchableSetting(isRussian ? "Режим проверки обновления" : "Update test mode")
    }
}

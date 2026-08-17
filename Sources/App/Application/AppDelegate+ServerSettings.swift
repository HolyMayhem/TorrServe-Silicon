import AppKit
import Foundation

@MainActor
extension AppDelegate {
    func loadTorrServerSettings() {
        guard !mainWindowModel.isLoadingServerSettings,
              !mainWindowModel.isSavingServerSettings else { return }

        guard processController.isRunning else {
            mainWindowModel.hasLoadedServerSettings = false
            mainWindowModel.serverSettingsResult = DiagnosticResult(
                kind: .warning,
                message: currentLanguage == .russian
                    ? "Запустите TorrServer, чтобы изменить его настройки."
                    : "Start TorrServer to edit its settings."
            )
            return
        }

        mainWindowModel.isLoadingServerSettings = true
        mainWindowModel.serverSettingsResult = DiagnosticResult(
            kind: .checking,
            message: ""
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let settings = try await self.nativeTorrServerAPI.settings()
                self.loadedTorrServerSettings = settings
                self.mainWindowModel.serverSettingsDraft = settings.draft
                self.mainWindowModel.savedServerSettingsDraft = settings.draft
                self.mainWindowModel.hasLoadedServerSettings = true
                self.mainWindowModel.serverSettingsResult = .idle
            } catch {
                self.loadedTorrServerSettings = nil
                self.mainWindowModel.hasLoadedServerSettings = false
                self.mainWindowModel.serverSettingsResult = DiagnosticResult(
                    kind: .failure,
                    message: self.currentLanguage == .russian
                        ? "Не удалось загрузить настройки TorrServer."
                        : "Could not load TorrServer settings."
                )
            }
            self.mainWindowModel.isLoadingServerSettings = false
        }
    }

    func saveTorrServerSettings() {
        guard !mainWindowModel.isSavingServerSettings else { return }
        guard let currentSettings = loadedTorrServerSettings else {
            loadTorrServerSettings()
            return
        }

        let draft = mainWindowModel.serverSettingsDraft.normalized
        if draft.useDisk {
            var isDirectory: ObjCBool = false
            guard !draft.torrentsSavePath.isEmpty,
                  FileManager.default.fileExists(
                    atPath: draft.torrentsSavePath,
                    isDirectory: &isDirectory
                  ),
                  isDirectory.boolValue else {
                mainWindowModel.serverSettingsResult = DiagnosticResult(
                    kind: .failure,
                    message: currentLanguage == .russian
                        ? "Выберите существующую папку для кеша."
                        : "Choose an existing cache folder."
                )
                return
            }
        }

        mainWindowModel.serverSettingsDraft = draft
        mainWindowModel.isSavingServerSettings = true
        mainWindowModel.serverSettingsResult = DiagnosticResult(
            kind: .checking,
            message: ""
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.nativeTorrServerAPI.updateSettings(
                    draft,
                    basedOn: currentSettings
                )
                let refreshed = try await self.nativeTorrServerAPI.settings()
                self.loadedTorrServerSettings = refreshed
                self.mainWindowModel.serverSettingsDraft = refreshed.draft
                self.mainWindowModel.savedServerSettingsDraft = refreshed.draft
                self.mainWindowModel.hasLoadedServerSettings = true
                self.mainWindowModel.serverSettingsResult = DiagnosticResult(
                    kind: .success,
                    message: self.currentLanguage == .russian
                        ? "Настройки сохранены."
                        : "Settings saved."
                )
                self.refreshStorage()
            } catch {
                self.mainWindowModel.serverSettingsResult = DiagnosticResult(
                    kind: .failure,
                    message: self.currentLanguage == .russian
                        ? "Не удалось сохранить настройки TorrServer."
                        : "Could not save TorrServer settings."
                )
            }
            self.mainWindowModel.isSavingServerSettings = false
        }
    }

    func chooseServerCacheFolder() {
        let panel = NSOpenPanel()
        panel.title = currentLanguage == .russian
            ? "Папка кеша TorrServer"
            : "TorrServer Cache Folder"
        panel.prompt = currentLanguage == .russian ? "Выбрать" : "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let currentPath = mainWindowModel.serverSettingsDraft.torrentsSavePath
        if !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        mainWindowModel.serverSettingsDraft.torrentsSavePath = url.path
        mainWindowModel.serverSettingsDraft.useDisk = true
        mainWindowModel.serverSettingsResult = .idle
    }
}

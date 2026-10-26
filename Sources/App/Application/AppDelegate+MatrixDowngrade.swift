import Foundation

@MainActor
extension AppDelegate {
    func loadOlderMatrixReleases() {
        guard mainWindowModel.developerMenuEnabled, !isDownloading,
              !mainWindowModel.isLoadingOlderMatrixReleases else { return }
        let path = executablePath
        mainWindowModel.isLoadingOlderMatrixReleases = true
        mainWindowModel.olderMatrixReleases = []
        mainWindowModel.matrixDowngradeMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { mainWindowModel.isLoadingOlderMatrixReleases = false }
            do {
                guard let installed = await releaseChecker.installedVersion(executablePath: path) else {
                    throw AppError("Не удалось определить версию выбранного TorrServer.")
                }
                let releases = try await releaseChecker.olderReleases(than: installed)
                guard path == executablePath, mainWindowModel.developerMenuEnabled else { return }
                mainWindowModel.torrServerVersion = installed.displayName
                mainWindowModel.olderMatrixReleases = releases
                if releases.isEmpty {
                    mainWindowModel.matrixDowngradeMessage = currentLanguage == .russian
                        ? "В последних 100 релизах нет более старой стабильной сборки для Apple Silicon."
                        : "No older stable Apple Silicon build was found in the latest 100 releases."
                }
            } catch {
                guard path == executablePath, mainWindowModel.developerMenuEnabled else { return }
                mainWindowModel.matrixDowngradeMessage = error.localizedDescription
            }
        }
    }

    func downgradeMatrix(to release: TorrServerDowngradeRelease) {
        guard mainWindowModel.developerMenuEnabled,
              mainWindowModel.olderMatrixReleases.contains(release),
              !mainWindowModel.isLoadingOlderMatrixReleases,
              !isDownloading, !isActivatingTorrServerUpdate,
              mainWindowModel.torrServerUpdateActivity == nil,
              mainWindowModel.statusKind != .working else { return }

        let previousPath = executablePath
        // Discard an already-running update check before locking the transfer.
        torrServerUpdateWorkItem?.cancel()
        torrServerUpdateCheckRevision += 1
        mainWindowModel.isCheckingForTorrServerUpdates = false
        mainWindowModel.matrixDowngradeMessage = nil
        beginTorrServerTransfer(kind: .downgrade, targetVersion: release.version)

        Task { [weak self] in
            guard let self else { return }
            defer {
                isActivatingTorrServerUpdate = false
                isDownloading = false
                hasAnnouncedRunningState = processController.isRunning
                saveCurrentPath()
                updateUI(for: processController.state)
                scheduleTorrServerUpdateCheck(clearingCurrentResult: true)
            }
            do {
                guard let installed = await releaseChecker.installedVersion(executablePath: previousPath),
                      let target = TorrServerVersion(release.version), target < installed,
                      TorrServerVersion(release.tagName) == target,
                      previousPath == executablePath else {
                    throw AppError("Выбранная версия уже не является более старой. Обновите список релизов.")
                }
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    downloader.downloadDarwinArm64(releaseTag: release.tagName) { [weak self] progress in
                        self?.updateTorrServerTransferProgress(progress)
                    } completion: { result in
                        continuation.resume(with: result)
                    }
                }
                guard previousPath == executablePath else {
                    throw AppError("Выбранный исполняемый файл изменился. Даунгрейд отменён.")
                }

                let restarting = processController.isRunning
                isActivatingTorrServerUpdate = true
                advanceTorrServerTransfer(to: restarting ? .restarting : .installing, progress: 0.97)
                let installer = TorrServerUpdateInstaller(
                    stop: {
                        await withCheckedContinuation { continuation in
                            self.stopServerPreservingDownloads { continuation.resume() }
                        }
                    },
                    start: { path in
                        try self.processController.start(executablePath: path)
                        guard let pid = self.processController.runningPID else {
                            throw AppError("Не удалось запустить TorrServer.")
                        }
                        return pid
                    },
                    isRunning: { self.processController.runningPID == $0 },
                    checkHealth: { try await self.nativeTorrServerAPI.checkHealth() }
                )
                try await installer.install(
                    executablePath: url.path, previousPath: previousPath,
                    restartingServer: restarting,
                    selectPath: {
                        self.mainWindowModel.path = $0
                        self.loadedTorrServerSettings = nil
                        self.mainWindowModel.hasLoadedServerSettings = false
                    }
                )
                // Keep discovery/manual updates working without immediately undoing the test.
                mainWindowModel.matrixDowngradeTestActive = true
                mainWindowModel.torrServerVersion = release.version
                mainWindowModel.torrServerUpdate = nil
                mainWindowModel.olderMatrixReleases = []
                failedAutomaticTorrServerVersion = nil
                completeTorrServerTransfer()
                mainWindowModel.matrixDowngradeMessage = currentLanguage == .russian
                    ? "Выбрана \(release.version). Предыдущий исполняемый файл сохранён. Проверка обновлений запускается обычным способом."
                    : "Selected \(release.version). The previous executable was retained. Normal update discovery will now run."
            } catch {
                mainWindowModel.torrServerUpdateActivity = nil
                mainWindowModel.matrixDowngradeMessage = error.localizedDescription
                showAlert(
                    title: currentLanguage == .russian ? "Даунгрейд MatriX не выполнен" : "MatriX downgrade failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func resumeMatrixAutomaticUpdates() {
        guard !isDownloading, !isActivatingTorrServerUpdate else { return }
        mainWindowModel.matrixDowngradeTestActive = false
        checkForTorrServerUpdate()
    }
}

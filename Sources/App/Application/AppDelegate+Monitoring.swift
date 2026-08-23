import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    func updatePopoverMaterial(with torrents: [NativeTorrent]) {
        let active = torrents.first(where: \.isActive)
        let selected = active ?? torrents.first
        popoverModel.activeTitle = selected?.displayTitle
        popoverModel.materialIsActive = active != nil
        popoverModel.activeSizeText = selected.map {
            Self.formatFileSize($0.torrentSize)
        } ?? ""
        popoverModel.bufferProgress = selected?.menuBufferProgress
        popoverModel.seeders = selected?.connectedSeeders ?? 0
        popoverModel.peers = selected.map {
            max($0.activePeers, $0.totalPeers)
        } ?? 0
    }

    func refreshQRCode() {
        let localURL = LocalWebUIAddress.url()
        popoverModel.webUIAddress = localURL.absoluteString
        popoverModel.qrImage = QRCodeGenerator.image(for: localURL.absoluteString)
    }

    func updateUI(for state: TorrServerProcessController.State) {
        let hasPath = hasExecutablePath
        updateSpeedMonitor(for: state)

        if isDownloading {
            let transferTitle = mainWindowModel.torrServerUpdateActivity?.title(
                language: currentLanguage
            ) ?? texts.downloading
            applyUIState(ServerPresentationState(
                dotColor: .systemOrange,
                statusText: transferTitle,
                statusTooltip: mainWindowModel.torrServerUpdateActivity?.detail(
                    language: currentLanguage
                ) ?? texts.downloading,
                canStart: false,
                canStop: false,
                canBrowse: false,
                canDownload: false,
                canOpenWeb: false,
                canEditPath: false,
                menuStatus: transferTitle
            ))
            return
        }

        switch state {
        case .stopped:
            clearServerConnectionIssue()
            applyUIState(ServerPresentationState(
                dotColor: .systemGray,
                statusText: hasPath ? texts.stopped : texts.chooseOrDownload,
                statusTooltip: hasPath ? texts.stopped : texts.chooseOrDownload,
                canStart: hasPath,
                canStop: false,
                canBrowse: true,
                canDownload: true,
                canOpenWeb: true,
                canEditPath: true,
                menuStatus: hasPath ? texts.stopped : texts.torrServerNotSelected
            ))
            loadedTorrServerSettings = nil
            mainWindowModel.hasLoadedServerSettings = false

        case .running(let pid):
            applyUIState(ServerPresentationState(
                dotColor: .systemGreen,
                statusText: texts.running(pid: pid),
                statusTooltip: texts.running(pid: pid),
                canStart: false,
                canStop: true,
                canBrowse: false,
                canDownload: false,
                canOpenWeb: true,
                canEditPath: false,
                menuStatus: texts.running(pid: pid)
            ))
            refreshStorage()
            if mainWindowModel.selectedSection == .server,
               !mainWindowModel.hasLoadedServerSettings {
                loadTorrServerSettings()
            }

        case .stopping:
            clearServerConnectionIssue()
            applyUIState(ServerPresentationState(
                dotColor: .systemOrange,
                statusText: texts.stopping,
                statusTooltip: texts.stopping,
                canStart: false,
                canStop: false,
                canBrowse: false,
                canDownload: false,
                canOpenWeb: false,
                canEditPath: false,
                menuStatus: texts.stopping
            ))

        case .failed(let message):
            clearServerConnectionIssue()
            applyUIState(ServerPresentationState(
                dotColor: .systemRed,
                statusText: texts.error(message),
                statusTooltip: texts.errorTooltip(message),
                canStart: hasPath,
                canStop: false,
                canBrowse: true,
                canDownload: true,
                canOpenWeb: true,
                canEditPath: true,
                menuStatus: texts.launchError
            ))
        }
    }

    func handleServerConnectionIssue(_ issue: String?) {
        guard let issue, !issue.isEmpty else {
            clearServerConnectionIssue()
            return
        }

        guard processController.isRunning else {
            clearServerConnectionIssue()
            return
        }

        consecutiveServerConnectionFailures += 1
        guard consecutiveServerConnectionFailures >= 2 else { return }
        mainWindowModel.serverConnectionIssue = issue
    }

    func clearServerConnectionIssue() {
        consecutiveServerConnectionFailures = 0
        mainWindowModel.serverConnectionIssue = nil
    }

    func updateSpeedMonitor(for state: TorrServerProcessController.State) {
        let shouldRun: Bool
        if case .running = state {
            shouldRun = true
        } else {
            shouldRun = false
        }

        if shouldRun {
            speedMonitor.start()
            startMenuBarMaterialTimer()
        } else {
            speedMonitor.stop()
            menuBarMaterialTimer?.invalidate()
            menuBarMaterialTimer = nil
            currentSpeedBytesPerSecond = nil
            speedHistory.removeAll()
            popoverModel.speedSamples = []
            updatePopoverMaterial(with: [])
        }
    }

    func startMenuBarMaterialTimer() {
        guard menuBarMaterialTimer == nil else { return }
        refreshPopoverMaterial()
        menuBarMaterialTimer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPopoverMaterial()
            }
        }
    }

    func recordSpeedSample(_ speed: Double?) {
        currentSpeedBytesPerSecond = speed

        if processController.isRunning {
            speedHistory.append(max(speed ?? 0, 0))
            if speedHistory.count > 30 {
                speedHistory.removeFirst(speedHistory.count - 30)
            }
        }

        popoverModel.speedSamples = speedHistory
        refreshSpeedDisplay()
    }

    func handleNotification(for state: TorrServerProcessController.State) {
        switch state {
        case .running:
            guard !hasAnnouncedRunningState else { return }
            hasAnnouncedRunningState = true
            notificationController.send(
                title: texts.serverStartedNotificationTitle,
                body: texts.serverStartedNotificationMessage
            )

        case .failed(let message):
            hasAnnouncedRunningState = false
            notificationController.send(
                title: texts.errorNotificationTitle,
                body: message
            )

        case .stopped:
            hasAnnouncedRunningState = false

        case .stopping:
            break
        }
    }

    func applyUIState(_ state: ServerPresentationState) {
        mainWindowModel.statusKind = mainStatusKind(for: state.dotColor)
        mainWindowModel.statusText = state.statusText
        mainWindowModel.statusTooltip = state.statusTooltip
        mainWindowModel.canStart = state.canStart
        mainWindowModel.canStop = state.canStop
        mainWindowModel.canOpenWeb = state.canOpenWeb
        mainWindowModel.canBrowse = state.canBrowse
        mainWindowModel.canDownload = state.canDownload
        mainWindowModel.canEditPath = state.canEditPath
        mainWindowModel.launchAtLogin = launchAtLoginController.isEnabled
        mainWindowModel.autoStartServer = UserDefaults.standard.bool(forKey: autoStartServerKey)
        mainWindowModel.autoUpdateTorrServer = UserDefaults.standard.bool(
            forKey: autoUpdateTorrServerKey
        )
        mainWindowModel.showSpeed = isSpeedDisplayEnabled
        mainWindowModel.hideDockIcon = UserDefaults.standard.bool(forKey: hideDockIconKey)
        if !isNotificationAuthorizationPending {
            mainWindowModel.notificationsEnabled = UserDefaults.standard.bool(
                forKey: notificationsEnabledKey
            )
        }
        mainWindowModel.jackettEnabled = UserDefaults.standard.bool(
            forKey: jackettSearchEnabledKey
        )
        mainWindowModel.speedUnit = currentSpeedDisplayUnit

        popoverModel.statusKind = mainStatusKind(for: state.dotColor)
        popoverModel.statusText = state.menuStatus
        popoverModel.isRunning = processController.isRunning
        popoverModel.canStart = state.canStart
        popoverModel.canStop = state.canStop
        popoverModel.canOpenWeb = state.canOpenWeb
        popoverModel.canDownload = state.canDownload
        popoverModel.isDownloading = isDownloading
        refreshSpeedDisplay()
    }

    func mainStatusKind(for color: NSColor) -> MainStatusKind {
        if color == .systemGreen {
            return .running
        }
        if color == .systemOrange {
            return .working
        }
        if color == .systemRed {
            return .failed
        }
        return .stopped
    }

    func refreshSpeedDisplay() {
        guard statusItem != nil else { return }

        let isServerRunning = processController.isRunning
        let speedText = currentSpeedBytesPerSecond.map {
            SpeedFormatter.string(
                bytesPerSecond: $0,
                unit: currentSpeedDisplayUnit
            )
        } ?? SpeedFormatter.string(
            bytesPerSecond: 0,
            unit: currentSpeedDisplayUnit
        )
        mainWindowModel.currentSpeedText = speedText
        popoverModel.speedText = speedText
        popoverModel.speedSamples = speedHistory

        let shouldShowSpeed = isSpeedDisplayEnabled
            && isServerRunning
            && (currentSpeedBytesPerSecond ?? 0) > 0
        let title = shouldShowSpeed
            ? currentSpeedBytesPerSecond.map {
                SpeedFormatter.string(
                    bytesPerSecond: $0,
                    unit: currentSpeedDisplayUnit
                )
            } ?? ""
            : ""

        statusItem.length = title.isEmpty
            ? NSStatusItem.squareLength
            : NSStatusItem.variableLength
        statusItem.button?.image = MenuBarIcon.makeImage()
        statusItem.button?.title = title.isEmpty ? "" : " \(title)"
        statusItem.button?.toolTip = title.isEmpty
            ? "TorrServer"
            : "TorrServer · \(title)"
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }

        let value = Double(bytes)
        if value >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", value / 1024 / 1024 / 1024)
        }

        return String(format: "%.0f MB", value / 1024 / 1024)
    }

    func initialExecutablePath() -> String {
        let savedPath = UserDefaults.standard.string(forKey: savedPathKey) ?? ""
        let bundledPath = Bundle.main.url(
            forResource: torrServerExecutableName,
            withExtension: nil
        )?.path

        guard let bundledPath else { return savedPath }
        guard !savedPath.isEmpty else { return bundledPath }

        let normalizedSavedPath = URL(fileURLWithPath: savedPath).standardizedFileURL.path
        let oldManagedSuffix = "/Library/Application Support/TorrServer Manager/\(torrServerExecutableName)"
        if normalizedSavedPath.hasSuffix(oldManagedSuffix)
            || !FileManager.default.fileExists(atPath: normalizedSavedPath) {
            return bundledPath
        }
        return normalizedSavedPath
    }

    func saveCurrentPath() {
        UserDefaults.standard.set(executablePath, forKey: savedPathKey)
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

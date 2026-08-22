import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    func updatePopoverMaterial(with torrents: [TorrentSummary]) {
        let active = torrents.first(where: \.isActive)
        let selected = active ?? torrents.first
        popoverModel.activeTitle = selected?.title
        popoverModel.materialIsActive = active != nil
        popoverModel.activeSizeText = selected.map {
            Self.formatFileSize($0.size)
        } ?? ""
        popoverModel.bufferProgress = selected?.bufferProgress
        popoverModel.seeders = selected?.seeders ?? 0
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
            applyUIState(
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
                menuStatus: transferTitle,
                statusIconColor: .systemGray
            )
            return
        }

        switch state {
        case .stopped:
            clearServerConnectionIssue()
            applyUIState(
                dotColor: .systemGray,
                statusText: hasPath ? texts.stopped : texts.chooseOrDownload,
                statusTooltip: hasPath ? texts.stopped : texts.chooseOrDownload,
                canStart: hasPath,
                canStop: false,
                canBrowse: true,
                canDownload: true,
                canOpenWeb: true,
                canEditPath: true,
                menuStatus: hasPath ? texts.stopped : texts.torrServerNotSelected,
                statusIconColor: .systemGray
            )
            loadedTorrServerSettings = nil
            mainWindowModel.hasLoadedServerSettings = false

        case .running(let pid):
            applyUIState(
                dotColor: .systemGreen,
                statusText: texts.running(pid: pid),
                statusTooltip: texts.running(pid: pid),
                canStart: false,
                canStop: true,
                canBrowse: false,
                canDownload: false,
                canOpenWeb: true,
                canEditPath: false,
                menuStatus: texts.running(pid: pid),
                statusIconColor: .systemGreen
            )
            refreshStorage()
            if mainWindowModel.selectedSection == .server,
               !mainWindowModel.hasLoadedServerSettings {
                loadTorrServerSettings()
            }

        case .stopping:
            clearServerConnectionIssue()
            applyUIState(
                dotColor: .systemOrange,
                statusText: texts.stopping,
                statusTooltip: texts.stopping,
                canStart: false,
                canStop: false,
                canBrowse: false,
                canDownload: false,
                canOpenWeb: false,
                canEditPath: false,
                menuStatus: texts.stopping,
                statusIconColor: .systemGray
            )

        case .failed(let message):
            clearServerConnectionIssue()
            applyUIState(
                dotColor: .systemRed,
                statusText: texts.error(message),
                statusTooltip: texts.errorTooltip(message),
                canStart: hasPath,
                canStop: false,
                canBrowse: true,
                canDownload: true,
                canOpenWeb: true,
                canEditPath: true,
                menuStatus: texts.launchError,
                statusIconColor: .systemGray
            )
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

    func applyUIState(
        dotColor: NSColor,
        statusText: String,
        statusTooltip: String,
        canStart: Bool,
        canStop: Bool,
        canBrowse: Bool,
        canDownload: Bool,
        canOpenWeb: Bool,
        canEditPath: Bool,
        menuStatus: String,
        statusIconColor: NSColor
    ) {
        mainWindowModel.statusKind = mainStatusKind(for: dotColor)
        mainWindowModel.statusText = statusText
        mainWindowModel.statusTooltip = statusTooltip
        mainWindowModel.canStart = canStart
        mainWindowModel.canStop = canStop
        mainWindowModel.canOpenWeb = canOpenWeb
        mainWindowModel.canBrowse = canBrowse
        mainWindowModel.canDownload = canDownload
        mainWindowModel.canEditPath = canEditPath
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

        popoverModel.statusKind = mainStatusKind(for: dotColor)
        popoverModel.statusText = menuStatus
        popoverModel.isRunning = processController.isRunning
        popoverModel.canStart = canStart
        popoverModel.canStop = canStop
        popoverModel.canOpenWeb = canOpenWeb
        popoverModel.canDownload = canDownload
        popoverModel.isDownloading = isDownloading
        currentStatusIconColor = statusIconColor
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

    var menuBarVisualState: MenuBarVisualState {
        if isDownloading { return .updating }
        if mainWindowModel.statusKind == .failed { return .failed }
        if mainWindowModel.statusKind == .working { return .working }
        guard processController.isRunning else { return .stopped }
        if currentTorrents.contains(where: { $0.status == 2 }) { return .buffering }
        if currentTorrents.contains(where: { $0.status == 3 })
            || (currentSpeedBytesPerSecond ?? 0) > 0 {
            return .streaming
        }
        return .running
    }

    func makeMenuBarImage(
        state: MenuBarVisualState,
        phase: CGFloat
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let color: NSColor
        switch state {
        case .stopped:
            color = NSColor(
                srgbRed: 82.0 / 255.0,
                green: 119.0 / 255.0,
                blue: 100.0 / 255.0,
                alpha: 1
            )
        case .running, .streaming:
            color = NSColor(
                srgbRed: 0.0 / 255.0,
                green: 239.0 / 255.0,
                blue: 98.0 / 255.0,
                alpha: 1
            )
        case .working, .buffering, .updating:
            color = NSColor(
                srgbRed: 220.0 / 255.0,
                green: 166.0 / 255.0,
                blue: 78.0 / 255.0,
                alpha: 1
            )
        case .failed:
            color = NSColor(
                srgbRed: 138.0 / 255.0,
                green: 81.0 / 255.0,
                blue: 88.0 / 255.0,
                alpha: 1
            )
        }

        let isPulsing = state == .streaming || state == .working
        let pulse = isPulsing ? phase * 0.10 : 0

        let outerGlowRect = NSRect(x: 0.35, y: 0.35, width: 17.3, height: 17.3)
        color.withAlphaComponent(0.13 + pulse * 0.45).setFill()
        NSBezierPath(ovalIn: outerGlowRect).fill()

        let glowRect = NSRect(x: 1.1, y: 1.1, width: 15.8, height: 15.8)
        color.withAlphaComponent(0.25 + pulse).setFill()
        NSBezierPath(ovalIn: glowRect).fill()

        let rect = NSRect(x: 2.45, y: 2.45, width: 13.1, height: 13.1)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()

        NSColor.white.withAlphaComponent(0.95).setFill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 10.1, y: 14.1))
        bolt.line(to: NSPoint(x: 6.25, y: 9.25))
        bolt.line(to: NSPoint(x: 8.65, y: 9.25))
        bolt.line(to: NSPoint(x: 7.65, y: 4.35))
        bolt.line(to: NSPoint(x: 12.15, y: 9.85))
        bolt.line(to: NSPoint(x: 9.75, y: 9.85))
        bolt.close()
        bolt.fill()

        if state == .updating {
            let ringRect = NSRect(x: 0.8, y: 0.8, width: 16.4, height: 16.4)
            let ring = NSBezierPath()
            ring.appendArc(
                withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
                radius: ringRect.width / 2,
                startAngle: 90 - phase * 360,
                endAngle: 220 - phase * 360
            )
            ring.lineWidth = 1.2
            ring.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
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
        updateMenuBarAnimationTimer()
        statusItem.button?.image = makeMenuBarImage(
            state: menuBarVisualState,
            phase: menuBarAnimationPhase
        )
        statusItem.button?.title = title.isEmpty ? "" : " \(title)"
        statusItem.button?.toolTip = title.isEmpty
            ? "TorrServer"
            : "TorrServer · \(title)"
    }

    func updateMenuBarAnimationTimer() {
        let state = menuBarVisualState
        let needsAnimation = state == .streaming || state == .working || state == .updating
        guard needsAnimation else {
            menuBarAnimationTimer?.invalidate()
            menuBarAnimationTimer = nil
            menuBarAnimationPhase = 0
            return
        }
        guard menuBarAnimationTimer == nil else { return }
        let interval: TimeInterval = state == .updating ? 0.14 : 0.8
        menuBarAnimationTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.menuBarAnimationPhase += state == .updating ? 0.08 : 1
                if self.menuBarAnimationPhase > 1 {
                    self.menuBarAnimationPhase = 0
                }
                self.statusItem.button?.image = self.makeMenuBarImage(
                    state: self.menuBarVisualState,
                    phase: self.menuBarAnimationPhase
                )
            }
        }
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

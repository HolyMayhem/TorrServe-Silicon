import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    @objc func chooseExecutable(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = texts.choosePanelTitle
        panel.message = texts.choosePanelMessage
        panel.prompt = texts.choosePanelPrompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            mainWindowModel.path = url.path
            saveCurrentPath()
            updateUI(for: processController.state)
        }
    }

    @objc func downloadLatestTorrServer(_ sender: Any?) {
        guard !isDownloading else { return }

        isDownloading = true
        updateUI(for: processController.state)

        downloader.downloadLatestDarwinArm64 { [weak self] result in
            guard let self else { return }
            self.isDownloading = false

            switch result {
            case .success(let url):
                self.mainWindowModel.path = url.path
                self.saveCurrentPath()
                self.updateUI(for: self.processController.state)
                self.showAlert(
                    title: self.texts.downloadDoneTitle,
                    message: self.texts.downloadDoneMessage
                )
                self.notificationController.send(
                    title: self.texts.updateInstalledNotificationTitle,
                    body: self.texts.downloadDoneMessage
                )
            case .failure(let error):
                self.updateUI(for: self.processController.state)
                self.showAlert(
                    title: self.texts.downloadFailedTitle,
                    message: error.localizedDescription
                )
                self.notificationController.send(
                    title: self.texts.errorNotificationTitle,
                    body: error.localizedDescription
                )
            }
        }
    }

    @objc func startServer(_ sender: Any?) {
        saveCurrentPath()

        guard hasExecutablePath else {
            showAlert(
                title: texts.chooseTorrServerAlertTitle,
                message: texts.chooseTorrServerAlertMessage
            )
            return
        }

        do {
            try processController.start(executablePath: executablePath)
        } catch {
            showAlert(
                title: texts.startFailedTitle,
                message: error.localizedDescription
            )
        }
    }

    @objc func stopServer(_ sender: Any?) {
        processController.stop()
    }

    @objc func openWebUI(_ sender: Any?) {
        NSWorkspace.shared.open(webUIURL)
    }

    @objc func addTorrentFromMenu(_ sender: Any?) {
        ensureWindowForCommand()
        mainWindowModel.selectedSection = .library
        libraryModel.chooseTorrentFiles(language: currentLanguage)
    }

    @objc func addMagnetFromMenu(_ sender: Any?) {
        ensureWindowForCommand()
        mainWindowModel.selectedSection = .library
        libraryModel.showsMagnetSheet = true
    }

    @objc func focusSearchFromMenu(_ sender: Any?) {
        ensureWindowForCommand()
        if mainWindowModel.jackettEnabled {
            mainWindowModel.selectedSection = .search
        } else {
            mainWindowModel.selectedSection = .library
        }
    }

    func ensureWindowForCommand() {
        if window == nil {
            buildWindow()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showMainWindow(_ sender: Any?) {
        if window == nil {
            buildWindow()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
        } catch {
            showAlert(
                title: texts.launchAtLoginFailedTitle,
                message: error.localizedDescription
            )
        }
        updateUI(for: processController.state)
    }

    func setAutoStartServer(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoStartServerKey)
        updateUI(for: processController.state)
    }

    func setSpeedInMenuBar(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: showSpeedInMenuBarKey)
        updateUI(for: processController.state)
    }

    func setHideDockIcon(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: hideDockIconKey)
        applyActivationPolicy(keepingWindowVisible: true)
        updateUI(for: processController.state)
    }

    func setLanguage(_ language: AppLanguage) {
        let shouldRefreshDiagnostics = mainWindowModel.isRunningDiagnostics
            || mainWindowModel.portDiagnostic.kind != .idle
            || mainWindowModel.processDiagnostic.kind != .idle
            || mainWindowModel.executableDiagnostic.kind != .idle

        diagnosticsRevision &+= 1
        currentLanguage = language
        mainWindowModel.isRunningDiagnostics = false
        mainWindowModel.isStoppingExternalProcesses = false
        mainWindowModel.portDiagnostic = .idle
        mainWindowModel.processDiagnostic = .idle
        mainWindowModel.processScan = .empty
        mainWindowModel.executableDiagnostic = .idle
        mainWindowModel.latestDiagnostic = .idle
        applyLanguage()
        updateUI(for: processController.state)
        updatePopoverMaterial(with: currentTorrents)

        if shouldRefreshDiagnostics {
            runFullDiagnostics()
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard !isNotificationAuthorizationPending else { return }

        mainWindowModel.notificationsEnabled = enabled
        mainWindowModel.notificationsAuthorizationPending = enabled
        isNotificationAuthorizationPending = enabled
        notificationController.setEnabled(enabled) { [weak self] granted, shouldOpenSettings in
            guard let self else { return }
            self.isNotificationAuthorizationPending = false
            self.mainWindowModel.notificationsAuthorizationPending = false
            self.mainWindowModel.notificationsEnabled = granted

            if enabled && !granted && shouldOpenSettings {
                self.openNotificationSettings()
            }
        }
    }

    func openNotificationSettings() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? productionBundleIdentifier
        let destinations = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for destination in destinations {
            guard let url = URL(string: destination) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    func setSpeedDisplayUnit(_ unit: SpeedDisplayUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: speedDisplayUnitKey)
        mainWindowModel.speedUnit = unit
        refreshSpeedDisplay()
    }

    func setJackettEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: jackettSearchEnabledKey)

        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            mainWindowModel.jackettEnabled = enabled
            if !enabled, mainWindowModel.selectedSection == .search {
                mainWindowModel.selectedSection = .library
            }
        }
    }

    func setMetadataProvider(_ provider: MetadataProvider) {
        do {
            try metadataSettings.save(selectedProvider: provider)
            mainWindowModel.metadataProvider = provider
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: "Metadata", message: error.localizedDescription)
            mainWindowModel.metadataProvider = metadataSettings.settings.selectedProvider
        }
    }

    func setMetadataAPIKey(_ value: String, provider: MetadataProvider) {
        do {
            try metadataSettings.save(apiKey: value, for: provider)
            let settings = metadataSettings.settings
            mainWindowModel.tmdbAPIKey = settings.tmdbAPIKey
            mainWindowModel.omdbAPIKey = settings.omdbAPIKey
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: provider.displayName, message: error.localizedDescription)
            let settings = metadataSettings.settings
            mainWindowModel.tmdbAPIKey = settings.tmdbAPIKey
            mainWindowModel.omdbAPIKey = settings.omdbAPIKey
        }
    }

    func setOverviewTranslationMode(_ mode: OverviewTranslationMode) {
        do {
            try metadataSettings.save(overviewTranslationMode: mode)
            mainWindowModel.overviewTranslationMode = mode
        } catch {
            showAlert(title: "Metadata", message: error.localizedDescription)
            mainWindowModel.overviewTranslationMode = metadataSettings.settings.overviewTranslationMode
        }
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "2.6.9"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "39"
        let credits = NSAttributedString(
            string: texts.aboutCredits,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TorrServer",
            .applicationVersion: "\(version) (\(build))",
            .credits: credits
        ])
    }

    var executablePath: String {
        mainWindowModel.path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasExecutablePath: Bool {
        !executablePath.isEmpty
    }

    var isSpeedDisplayEnabled: Bool {
        UserDefaults.standard.bool(forKey: showSpeedInMenuBarKey)
    }

    var currentSpeedDisplayUnit: SpeedDisplayUnit {
        guard
            let rawValue = UserDefaults.standard.string(forKey: speedDisplayUnitKey),
            let unit = SpeedDisplayUnit(rawValue: rawValue)
        else {
            return .automatic
        }
        return unit
    }

    var currentLanguage: AppLanguage {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: languageKey),
               let language = AppLanguage(rawValue: rawValue) {
                return language
            }
            return .systemDefault
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
        }
    }

    var texts: Texts {
        Texts(language: currentLanguage)
    }

    func registerDefaultSettings() {
        UserDefaults.standard.register(defaults: [
            showSpeedInMenuBarKey: true,
            hideDockIconKey: false,
            notificationsEnabledKey: false,
            jackettSearchEnabledKey: true,
            speedDisplayUnitKey: SpeedDisplayUnit.automatic.rawValue
        ])
    }

    func applyActivationPolicy(keepingWindowVisible: Bool = false) {
        let shouldHideDockIcon = UserDefaults.standard.bool(forKey: hideDockIconKey)
        let shouldRestoreWindow = keepingWindowVisible && window?.isVisible == true
        NSApp.setActivationPolicy(shouldHideDockIcon ? .accessory : .regular)

        guard shouldRestoreWindow else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.window.orderFrontRegardless()
            self.window.makeKey()
        }
    }
}

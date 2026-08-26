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
            scheduleTorrServerUpdateCheck(clearingCurrentResult: true)
        }
    }

    @objc func downloadLatestTorrServer(_ sender: Any?) {
        guard !isDownloading else { return }

        beginTorrServerTransfer(kind: .download, targetVersion: nil)

        downloader.downloadLatestDarwinArm64 { [weak self] progress in
            self?.updateTorrServerTransferProgress(progress)
        } completion: { [weak self] result in
            guard let self else { return }
            self.isDownloading = false

            switch result {
            case .success(let url):
                self.mainWindowModel.path = url.path
                self.saveCurrentPath()
                self.completeTorrServerTransfer()
                self.updateUI(for: self.processController.state)
                self.scheduleTorrServerUpdateCheck(clearingCurrentResult: true)
                self.showAlert(
                    title: self.texts.downloadDoneTitle,
                    message: self.texts.downloadDoneMessage
                )
                self.notificationController.send(
                    title: self.texts.updateInstalledNotificationTitle,
                    body: self.texts.downloadDoneMessage
                )
            case .failure(let error):
                self.mainWindowModel.torrServerUpdateActivity = nil
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

    func checkForTorrServerUpdate() {
        guard !isDownloading else { return }

        let path = executablePath
        torrServerUpdateCheckRevision += 1
        let revision = torrServerUpdateCheckRevision

        Task { [weak self] in
            guard let self else { return }
            let installedVersion = await self.releaseChecker.installedVersion(
                executablePath: path
            )
            guard path == self.executablePath,
                  revision == self.torrServerUpdateCheckRevision else { return }

            self.mainWindowModel.torrServerVersion = installedVersion?.displayName
            guard let installedVersion else {
                self.mainWindowModel.torrServerUpdate = nil
                return
            }

            do {
                let update = try await self.releaseChecker.availableUpdate(
                    installedVersion: installedVersion
                )
                guard path == self.executablePath,
                      revision == self.torrServerUpdateCheckRevision else { return }
                if let update,
                   UserDefaults.standard.bool(forKey: autoUpdateTorrServerKey) {
                    self.mainWindowModel.torrServerUpdate = nil
                    self.automaticallyInstallTorrServerUpdate(update)
                } else {
                    self.mainWindowModel.torrServerUpdate = update
                }
            } catch {
                // A temporary GitHub or network error must not interrupt normal use.
            }
        }
    }

    func scheduleTorrServerUpdateCheck(clearingCurrentResult: Bool = false) {
        torrServerUpdateWorkItem?.cancel()
        if clearingCurrentResult {
            mainWindowModel.torrServerVersion = nil
            mainWindowModel.torrServerUpdate = nil
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.checkForTorrServerUpdate()
        }
        torrServerUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    func schedulePeriodicTorrServerUpdateChecks() {
        torrServerUpdateTimer?.invalidate()
        torrServerUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: 6 * 60 * 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForTorrServerUpdate()
            }
        }
    }

    private func automaticallyInstallTorrServerUpdate(
        _ update: TorrServerAvailableUpdate
    ) {
        guard !isDownloading else { return }

        let shouldRestartServer = processController.isRunning
        mainWindowModel.torrServerUpdate = nil
        beginTorrServerTransfer(
            kind: .update,
            targetVersion: update.latestVersion
        )

        downloader.downloadLatestDarwinArm64 { [weak self] progress in
            self?.updateTorrServerTransferProgress(progress)
        } completion: { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let url):
                let finishInstallation: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.finishAutomaticTorrServerUpdate(
                        at: url,
                        restartingServer: shouldRestartServer
                    )
                }

                if shouldRestartServer {
                    self.advanceTorrServerTransfer(to: .restarting, progress: 0.97)
                    self.processController.stop(completion: finishInstallation)
                } else {
                    finishInstallation()
                }

            case .failure(let error):
                self.isDownloading = false
                self.mainWindowModel.torrServerUpdateActivity = nil
                self.mainWindowModel.torrServerUpdate = update
                self.updateUI(for: self.processController.state)
                self.notificationController.send(
                    title: self.texts.errorNotificationTitle,
                    body: error.localizedDescription
                )
            }
        }
    }

    func installAvailableTorrServerUpdate() {
        guard let update = mainWindowModel.torrServerUpdate else { return }
        automaticallyInstallTorrServerUpdate(update)
    }

    private func finishAutomaticTorrServerUpdate(
        at url: URL,
        restartingServer: Bool
    ) {
        mainWindowModel.path = url.path
        mainWindowModel.torrServerUpdate = nil
        if let targetVersion = mainWindowModel.torrServerUpdateActivity?.targetVersion {
            mainWindowModel.torrServerVersion = targetVersion
        }
        saveCurrentPath()
        isDownloading = false
        completeTorrServerTransfer()
        updateUI(for: processController.state)

        if restartingServer {
            startServer(nil)
        }

        scheduleTorrServerUpdateCheck(clearingCurrentResult: true)
        notificationController.send(
            title: texts.updateInstalledNotificationTitle,
            body: texts.downloadDoneMessage
        )
    }

    private func beginTorrServerTransfer(
        kind: TorrServerUpdateActivity.Kind,
        targetVersion: String?
    ) {
        isDownloading = true
        mainWindowModel.torrServerUpdateActivity = TorrServerUpdateActivity(
            kind: kind,
            stage: .preparing,
            progress: 0.03,
            targetVersion: targetVersion
        )
        updateUI(for: processController.state)
    }

    private func updateTorrServerTransferProgress(_ downloadProgress: Double) {
        guard let activity = mainWindowModel.torrServerUpdateActivity else { return }
        let isInstalling = downloadProgress >= 0.995
        mainWindowModel.torrServerUpdateActivity = TorrServerUpdateActivity(
            kind: activity.kind,
            stage: isInstalling ? .installing : .downloading,
            progress: isInstalling ? 0.93 : 0.06 + (downloadProgress * 0.84),
            targetVersion: activity.targetVersion
        )
    }

    private func advanceTorrServerTransfer(
        to stage: TorrServerUpdateActivity.Stage,
        progress: Double
    ) {
        guard let activity = mainWindowModel.torrServerUpdateActivity else { return }
        mainWindowModel.torrServerUpdateActivity = TorrServerUpdateActivity(
            kind: activity.kind,
            stage: stage,
            progress: progress,
            targetVersion: activity.targetVersion
        )
    }

    private func completeTorrServerTransfer() {
        guard let activity = mainWindowModel.torrServerUpdateActivity else { return }
        let completed = TorrServerUpdateActivity(
            kind: activity.kind,
            stage: .completed,
            progress: 1,
            targetVersion: activity.targetVersion
        )
        mainWindowModel.torrServerUpdateActivity = completed

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self,
                  self.mainWindowModel.torrServerUpdateActivity == completed else { return }
            self.mainWindowModel.torrServerUpdateActivity = nil
            self.updateUI(for: self.processController.state)
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

    func setAutoUpdateTorrServer(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoUpdateTorrServerKey)
        mainWindowModel.autoUpdateTorrServer = enabled

        if enabled, let update = mainWindowModel.torrServerUpdate {
            mainWindowModel.torrServerUpdate = nil
            automaticallyInstallTorrServerUpdate(update)
        } else if enabled {
            scheduleTorrServerUpdateCheck(clearingCurrentResult: true)
        }
    }

    func setMenuBarPreferences(_ preferences: MenuBarPreferences) {
        var normalized = preferences
        normalized.sectionOrder = MenuBarPreferences.normalizedOrder(
            preferences.sectionOrder
        )

        if !normalized.isIconVisible && mainWindowModel.hideDockIcon {
            UserDefaults.standard.set(false, forKey: hideDockIconKey)
            mainWindowModel.hideDockIcon = false
            applyActivationPolicy(keepingWindowVisible: true)
        }

        menuBarPreferencesStore.save(normalized)
        mainWindowModel.menuBarPreferences = normalized
        popoverModel.preferences = normalized
        statusItem?.isVisible = normalized.isIconVisible
        if !normalized.showsQRCode {
            popoverModel.showsQRCode = false
        }
        refreshSpeedDisplay()
        synchronizePopoverLayout()
    }

    func setHideDockIcon(_ enabled: Bool) {
        if enabled && !mainWindowModel.menuBarPreferences.isIconVisible {
            var preferences = mainWindowModel.menuBarPreferences
            preferences.isIconVisible = true
            setMenuBarPreferences(preferences)
        }
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

    func setMetadataSource(_ source: MetadataSourceMode) {
        do {
            try metadataSettings.save(selectedSource: source)
            mainWindowModel.metadataSource = source
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: "Metadata", message: error.localizedDescription)
            mainWindowModel.metadataSource = metadataSettings.settings.selectedSource
        }
    }

    func setAniListEnabled(_ enabled: Bool) {
        do {
            try metadataSettings.save(aniListEnabled: enabled)
            mainWindowModel.aniListEnabled = enabled
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: "AniList", message: error.localizedDescription)
            mainWindowModel.aniListEnabled = metadataSettings.settings.aniListEnabled
        }
    }

    func setMetadataAPIKeyMode(_ mode: MetadataAPIKeyMode) {
        mainWindowModel.metadataKeysDiagnostic = .idle
        do {
            try metadataSettings.save(apiKeyMode: mode)
            mainWindowModel.metadataAPIKeyMode = mode
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: "Metadata", message: error.localizedDescription)
            mainWindowModel.metadataAPIKeyMode = metadataSettings.settings.apiKeyMode
        }
    }

    func setCombinedMetadataOrder(_ providers: [MetadataProvider]) {
        do {
            try metadataSettings.save(combinedOrder: providers)
            mainWindowModel.combinedMetadataOrder = metadataSettings.settings.combinedOrder
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: "Metadata", message: error.localizedDescription)
            mainWindowModel.combinedMetadataOrder = metadataSettings.settings.combinedOrder
        }
    }

    func setMetadataAPIKey(_ value: String, provider: MetadataProvider) {
        mainWindowModel.metadataAPIKeyTestStates[provider] = .idle
        mainWindowModel.metadataKeysDiagnostic = .idle
        do {
            try metadataSettings.save(apiKey: value, for: provider)
            let settings = metadataSettings.settings
            mainWindowModel.tmdbAPIKey = settings.tmdbAPIKey
            mainWindowModel.omdbAPIKey = settings.omdbAPIKey
            mainWindowModel.kinopoiskAPIKey = settings.kinopoiskAPIKey
            libraryModel.metadataConfigurationChanged()
        } catch {
            showAlert(title: provider.displayName, message: error.localizedDescription)
            let settings = metadataSettings.settings
            mainWindowModel.tmdbAPIKey = settings.tmdbAPIKey
            mainWindowModel.omdbAPIKey = settings.omdbAPIKey
            mainWindowModel.kinopoiskAPIKey = settings.kinopoiskAPIKey
        }
    }

    func testMetadataAPIKey(_ value: String, provider: MetadataProvider) {
        let apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            mainWindowModel.metadataAPIKeyTestStates[provider] = .invalid
            return
        }
        guard mainWindowModel.metadataAPIKeyTestStates[provider] != .testing else {
            return
        }

        mainWindowModel.metadataAPIKeyTestStates[provider] = .testing
        Task { [weak self] in
            guard let self else { return }
            let result = await metadataAPIKeyValidator.validate(
                provider: provider,
                apiKey: apiKey
            )
            guard !Task.isCancelled else { return }
            guard currentMetadataAPIKey(for: provider)
                .trimmingCharacters(in: .whitespacesAndNewlines) == apiKey else {
                return
            }

            switch result {
            case .valid:
                mainWindowModel.metadataAPIKeyTestStates[provider] = .valid
            case .invalid:
                mainWindowModel.metadataAPIKeyTestStates[provider] = .invalid
            case .rateLimited:
                mainWindowModel.metadataAPIKeyTestStates[provider] = .rateLimited
            case .unavailable:
                mainWindowModel.metadataAPIKeyTestStates[provider] = .unavailable
            }
        }
    }

    func testAllMetadataAPIKeys() {
        guard !mainWindowModel.isTestingAllMetadataAPIKeys else { return }

        mainWindowModel.isTestingAllMetadataAPIKeys = true
        mainWindowModel.metadataKeysDiagnostic = DiagnosticResult(kind: .checking, message: "")
        let providers = MetadataProvider.apiKeyProviders
        for provider in providers {
            mainWindowModel.metadataAPIKeyTestStates[provider] = .testing
        }

        Task { [weak self] in
            guard let self else { return }
            var results: [MetadataProvider: MetadataAPIKeyValidationResult] = [:]

            for provider in providers {
                let apiKey = self.metadataSettings.activeAPIKey(for: provider)
                results[provider] = await self.metadataAPIKeyValidator.validate(
                    provider: provider,
                    apiKey: apiKey
                )
            }

            for provider in providers {
                switch results[provider] ?? .unavailable {
                case .valid:
                    self.mainWindowModel.metadataAPIKeyTestStates[provider] = .valid
                case .invalid:
                    self.mainWindowModel.metadataAPIKeyTestStates[provider] = .invalid
                case .rateLimited:
                    self.mainWindowModel.metadataAPIKeyTestStates[provider] = .rateLimited
                case .unavailable:
                    self.mainWindowModel.metadataAPIKeyTestStates[provider] = .unavailable
                }
            }

            let acceptedCount = results.values.filter {
                $0 == .valid || $0 == .rateLimited
            }.count
            let hasInvalidKey = results.values.contains(.invalid)
            let hasUnavailableProvider = results.values.contains(.unavailable)
            let language = self.currentLanguage
            let result = DiagnosticResult(
                kind: hasInvalidKey
                    ? .failure
                    : (hasUnavailableProvider || acceptedCount < providers.count
                        ? .warning
                        : .success),
                message: language == .russian
                    ? "Проверено ключей: \(acceptedCount) из \(providers.count)."
                    : "API keys accepted: \(acceptedCount) of \(providers.count)."
            )
            self.mainWindowModel.metadataKeysDiagnostic = result
            self.mainWindowModel.latestDiagnostic = result
            self.mainWindowModel.isTestingAllMetadataAPIKeys = false
        }
    }

    private func currentMetadataAPIKey(for provider: MetadataProvider) -> String {
        switch provider {
        case .tmdb:
            return mainWindowModel.tmdbAPIKey
        case .omdb:
            return mainWindowModel.omdbAPIKey
        case .kinopoisk:
            return mainWindowModel.kinopoiskAPIKey
        case .anilist:
            return ""
        }
    }

    func setOverviewTranslationMode(_ mode: OverviewTranslationMode) {
        do {
            try metadataSettings.save(overviewTranslationMode: mode)
            mainWindowModel.overviewTranslationMode = mode
            libraryModel.metadataConfigurationChanged()
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
        mainWindowModel.menuBarPreferences.showsSpeed
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
            autoUpdateTorrServerKey: false,
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

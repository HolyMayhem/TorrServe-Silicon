import AppKit
import Combine
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "TorrServer"
        statusItem.button?.setAccessibilityLabel("TorrServer status")
        statusItem.button?.imagePosition = .imageTrailing
        statusItem.button?.imageScaling = .scaleProportionallyUpOrDown
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleStatusPopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        var preferences = menuBarPreferencesStore.load()
        if !preferences.isIconVisible,
           UserDefaults.standard.bool(forKey: hideDockIconKey) {
            UserDefaults.standard.set(false, forKey: hideDockIconKey)
            applyActivationPolicy()
        }
        preferences.sectionOrder = MenuBarPreferences.normalizedOrder(
            preferences.sectionOrder
        )
        mainWindowModel.menuBarPreferences = preferences
        popoverModel.preferences = preferences
        statusItem.isVisible = preferences.isIconVisible

        popoverModel.onStart = { [weak self] in self?.startServer(nil) }
        popoverModel.onStop = { [weak self] in self?.stopServer(nil) }
        popoverModel.onOpenWeb = { [weak self] in self?.openWebUI(nil) }
        popoverModel.onShowWindow = { [weak self] in
            self?.statusPopover.performClose(nil)
            self?.showMainWindow(nil)
        }
        popoverModel.onDownload = { [weak self] in self?.downloadLatestTorrServer(nil) }
        popoverModel.onRestart = { [weak self] in self?.restartServerFromMenu() }
        popoverModel.onShowSettings = { [weak self] in
            self?.statusPopover.performClose(nil)
            self?.showSettingsWindow(category: .menuBar)
        }
        popoverModel.onShowUpdates = { [weak self] in
            self?.statusPopover.performClose(nil)
            self?.showSettingsWindow(category: .updates)
            if self?.mainWindowModel.torrServerUpdate == nil {
                self?.scheduleTorrServerUpdateCheck()
            }
        }
        popoverModel.onShowLibrary = { [weak self] in
            self?.statusPopover.performClose(nil)
            self?.ensureWindowForCommand()
            self?.mainWindowModel.selectedSection = .library
        }
        menuBarServerInfoObservation = mainWindowModel.$torrServerVersion
            .combineLatest(mainWindowModel.$torrServerUpdate,
                           mainWindowModel.$isCheckingForTorrServerUpdates,
                           mainWindowModel.$torrServerUpdateActivity)
            .sink { [weak self] version, update, checking, activity in
                self?.popoverModel.installedVersion = version
                self?.popoverModel.availableVersion = update?.latestVersion
                self?.popoverModel.isCheckingForUpdate = checking
                self?.popoverModel.isInstallingUpdate = activity != nil && activity?.stage != .completed
            }
        popoverModel.onQuit = {
            NSApp.terminate(nil)
        }
        popoverModel.onQRCodeVisibilityChanged = { [weak self] in
            self?.synchronizePopoverLayout()
        }
        statusPopover = MenuBarPopoverController(model: popoverModel)
        statusPopover.onClose = { [weak self] in
            self?.stopMonitoringPopoverDismissal()
            self?.cancelMenuBarCacheRefresh()
        }

        refreshQRCode()
    }

    @objc func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if statusPopover.isShown {
            statusPopover.performClose(sender)
            return
        }

        refreshQRCode()
        popoverModel.showsQRCode = popoverModel.preferences.showsQRCode
            && popoverModel.preferences.expandsQRCodeOnOpen
        refreshPopoverMaterial()
        synchronizePopoverLayout()
        NSApp.activate(ignoringOtherApps: true)
        statusPopover.show(relativeTo: button)
        beginMonitoringPopoverDismissal()
    }

    func beginMonitoringPopoverDismissal() {
        stopMonitoringPopoverDismissal()

        localPopoverEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard
                let self,
                self.statusPopover.isShown
            else {
                return event
            }

            let popoverWindow = self.statusPopover.window
            let statusItemWindow = self.statusItem.button?.window
            if event.window === popoverWindow || event.window === statusItemWindow {
                return event
            }

            self.statusPopover.performClose(nil)
            return event
        }

        globalPopoverEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.statusPopover.isShown == true else { return }
                self?.statusPopover.performClose(nil)
            }
        }
    }

    func stopMonitoringPopoverDismissal() {
        if let localPopoverEventMonitor {
            NSEvent.removeMonitor(localPopoverEventMonitor)
            self.localPopoverEventMonitor = nil
        }

        if let globalPopoverEventMonitor {
            NSEvent.removeMonitor(globalPopoverEventMonitor)
            self.globalPopoverEventMonitor = nil
        }
    }

    func synchronizePopoverLayout() {
        statusPopover?.synchronizeLayout()
    }

    func applyLanguage() {
        let language = currentLanguage
        let texts = self.texts

        buildMainMenu()
        window?.title = texts.title
        settingsWindow?.title = language == .russian ? "Настройки" : "Settings"
        mainWindowModel.language = language
        popoverModel.language = language
        libraryModel.setMetadataLanguage(language)
        updateUI(for: processController.state)
        refreshSpeedDisplay()
    }

    func refreshPopoverMaterial() {
        guard processController.isRunning else {
            currentTorrents = []
            popoverModel.isLoadingMaterial = false
            updatePopoverMaterial(with: [])
            cancelMenuBarCacheRefresh()
            refreshSpeedDisplay()
            return
        }

        guard !popoverModel.isLoadingMaterial else { return }
        popoverModel.isLoadingMaterial = true
        let pid = processController.runningPID
        Task {
            defer { popoverModel.isLoadingMaterial = false }
            do {
                let torrents = try await nativeTorrServerAPI.listTorrents()
                guard processController.runningPID == pid else { return }
                currentTorrents = torrents
                updatePopoverMaterial(with: torrents)
                refreshMenuBarCache(torrents: torrents)
                if libraryModel.isPollingActive {
                    libraryModel.applyServerSnapshot(torrents)
                }
            } catch {
                guard processController.runningPID == pid else { return }
                currentTorrents = []
                updatePopoverMaterial(with: [])
                popoverModel.activeTorrentCount = nil
                cancelMenuBarCacheRefresh()
                if libraryModel.isPollingActive {
                    libraryModel.applyServerFailure(error)
                }
            }
            synchronizePopoverLayout()
            refreshSpeedDisplay()
        }
    }

    func restartServerFromMenu() {
        guard processController.isRunning, popoverModel.canStop,
              !isDownloading, !isActivatingTorrServerUpdate, !popoverModel.isRestarting else { return }
        let path = executablePath
        popoverModel.isRestarting = true
        stopServerPreservingDownloads { [weak self] in
            guard let self else { return }
            defer {
                self.popoverModel.isRestarting = false
                self.hasAnnouncedRunningState = self.processController.isRunning
            }
            guard !self.isPreparingForTermination, !self.isDownloading,
                  self.executablePath == path else { return }
            self.startServer(nil)
        }
    }

    func cancelMenuBarCacheRefresh() {
        menuBarCacheRevision += 1
        menuBarCacheTask?.cancel()
        menuBarCacheTask = nil
        menuBarCacheHashes = []
        popoverModel.cacheSnapshot = nil
    }

    func refreshMenuBarCache(torrents: [NativeTorrent]) {
        guard statusPopover.isShown, popoverModel.preferences.showsCache,
              processController.isRunning else {
            cancelMenuBarCacheRefresh()
            return
        }
        let hashes = Set(torrents.filter(\.isActive).map(\.hash).filter { !$0.isEmpty })
        if hashes != menuBarCacheHashes { cancelMenuBarCacheRefresh() }
        menuBarCacheHashes = hashes
        guard !hashes.isEmpty else {
            popoverModel.cacheSnapshot = .empty
            return
        }
        guard menuBarCacheTask == nil else { return }
        let revision = menuBarCacheRevision
        let pid = processController.runningPID
        let api = nativeTorrServerAPI
        menuBarCacheTask = Task { [weak self] in
            defer {
                if let self, revision == self.menuBarCacheRevision { self.menuBarCacheTask = nil }
            }
            let snapshot: MenuBarCacheSnapshot?
            do {
                snapshot = try await withThrowingTaskGroup(of: (Int64, Int64).self) { group in
                    for hash in hashes {
                        group.addTask {
                            let state = try await api.cacheState(hash: hash)
                            return (state.filled, state.capacity)
                        }
                    }
                    var buffers: [(used: Int64, capacity: Int64)] = []
                    for try await buffer in group { buffers.append(buffer) }
                    return MenuBarCacheSnapshot.aggregate(buffers)
                }
            } catch {
                snapshot = nil
            }
            guard let self, !Task.isCancelled, revision == self.menuBarCacheRevision,
                  pid == self.processController.runningPID,
                  self.statusPopover.isShown, self.popoverModel.preferences.showsCache else { return }
            self.popoverModel.cacheSnapshot = snapshot
        }
    }
}

import AppKit
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
        popoverModel.onQuit = {
            NSApp.terminate(nil)
        }
        popoverModel.onQRCodeVisibilityChanged = { [weak self] in
            self?.synchronizePopoverLayout()
        }
        statusPopover = MenuBarPopoverController(model: popoverModel)
        statusPopover.onClose = { [weak self] in
            self?.stopMonitoringPopoverDismissal()
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
            refreshSpeedDisplay()
            return
        }

        guard !popoverModel.isLoadingMaterial else { return }
        popoverModel.isLoadingMaterial = true
        Task {
            defer { popoverModel.isLoadingMaterial = false }
            do {
                let torrents = try await nativeTorrServerAPI.listTorrents()
                currentTorrents = torrents
                updatePopoverMaterial(with: torrents)
                if libraryModel.isPollingActive {
                    libraryModel.applyServerSnapshot(torrents)
                }
            } catch {
                currentTorrents = []
                updatePopoverMaterial(with: [])
                if libraryModel.isPollingActive {
                    libraryModel.applyServerFailure(error)
                }
            }
            synchronizePopoverLayout()
            refreshSpeedDisplay()
        }
    }
}

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
        statusPopover = NSPopover()
        statusPopover.behavior = .transient
        statusPopover.animates = true
        statusPopover.delegate = self
        statusPopover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(model: popoverModel)
        )

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
        statusPopover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        beginMonitoringPopoverDismissal()
        synchronizePopoverLayout()

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.statusPopover.isShown,
                let contentView = self.statusPopover.contentViewController?.view,
                let popoverWindow = contentView.window
            else {
                return
            }

            popoverWindow.makeKey()
            popoverWindow.makeFirstResponder(contentView)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringPopoverDismissal()
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

            let popoverWindow = self.statusPopover.contentViewController?.view.window
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
        guard
            statusPopover != nil,
            let contentView = statusPopover.contentViewController?.view
        else {
            return
        }

        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            statusPopover.contentSize = fittingSize
        }

        guard statusPopover.isShown else { return }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let popoverWindow = self.statusPopover.contentViewController?.view.window,
                let button = self.statusItem.button,
                let screen = button.window?.screen ?? popoverWindow.screen ?? NSScreen.main
            else {
                return
            }

            var frame = popoverWindow.frame
            let horizontalMargin: CGFloat = 4
            let verticalMargin: CGFloat = 4
            let minimumY = screen.visibleFrame.minY + verticalMargin
            let maximumY = screen.frame.maxY - verticalMargin
            let minimumX = screen.frame.minX + horizontalMargin
            let maximumX = screen.frame.maxX - horizontalMargin

            if frame.maxY > maximumY {
                frame.origin.y -= frame.maxY - maximumY
            }
            if frame.minY < minimumY {
                frame.origin.y = minimumY
            }
            if frame.minX < minimumX {
                frame.origin.x = minimumX
            }
            if frame.maxX > maximumX {
                frame.origin.x -= frame.maxX - maximumX
            }

            popoverWindow.setFrameOrigin(frame.origin)
        }
    }

    func applyLanguage() {
        let language = currentLanguage
        let texts = self.texts

        buildMainMenu()
        window?.title = texts.title
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

import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TorrServer"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true

        mainWindowModel.path = initialExecutablePath()
        mainWindowModel.language = currentLanguage
        mainWindowModel.jackettEnabled = UserDefaults.standard.bool(
            forKey: jackettSearchEnabledKey
        )
        let metadataProviderSettings = metadataSettings.settings
        mainWindowModel.metadataProvider = metadataProviderSettings.selectedProvider
        mainWindowModel.tmdbAPIKey = metadataProviderSettings.tmdbAPIKey
        mainWindowModel.omdbAPIKey = metadataProviderSettings.omdbAPIKey
        mainWindowModel.overviewTranslationMode = metadataProviderSettings.overviewTranslationMode
        mainWindowModel.onPathChanged = { [weak self] _ in
            guard let self else { return }
            self.saveCurrentPath()
            self.updateUI(for: self.processController.state)
        }
        mainWindowModel.onChoose = { [weak self] in self?.chooseExecutable(nil) }
        mainWindowModel.onDownload = { [weak self] in self?.downloadLatestTorrServer(nil) }
        mainWindowModel.onStart = { [weak self] in self?.startServer(nil) }
        mainWindowModel.onStop = { [weak self] in self?.stopServer(nil) }
        mainWindowModel.onOpenContacts = {
            NSWorkspace.shared.open(contactsURL)
        }
        mainWindowModel.onOpenWeb = { [weak self] in self?.openWebUI(nil) }
        mainWindowModel.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        mainWindowModel.onAutoStartChanged = { [weak self] enabled in
            self?.setAutoStartServer(enabled)
        }
        mainWindowModel.onShowSpeedChanged = { [weak self] enabled in
            self?.setSpeedInMenuBar(enabled)
        }
        mainWindowModel.onHideDockIconChanged = { [weak self] enabled in
            self?.setHideDockIcon(enabled)
        }
        mainWindowModel.onNotificationsChanged = { [weak self] enabled in
            self?.setNotificationsEnabled(enabled)
        }
        mainWindowModel.onJackettEnabledChanged = { [weak self] enabled in
            self?.setJackettEnabled(enabled)
        }
        mainWindowModel.onMetadataProviderChanged = { [weak self] provider in
            self?.setMetadataProvider(provider)
        }
        mainWindowModel.onMetadataAPIKeyChanged = { [weak self] provider, value in
            self?.setMetadataAPIKey(value, provider: provider)
        }
        mainWindowModel.onOverviewTranslationModeChanged = { [weak self] mode in
            self?.setOverviewTranslationMode(mode)
        }
        mainWindowModel.onSpeedUnitChanged = { [weak self] unit in
            self?.setSpeedDisplayUnit(unit)
        }
        mainWindowModel.onLanguageChanged = { [weak self] language in
            self?.setLanguage(language)
        }
        mainWindowModel.onSectionChanged = { [weak self] section in
            self?.resizeWindow(for: section)
        }
        mainWindowModel.onOpenIINADownload = {
            NSWorkspace.shared.open(iinaDownloadURL)
        }
        mainWindowModel.onOpenVLCDownload = {
            NSWorkspace.shared.open(vlcDownloadURL)
        }
        mainWindowModel.onOpenInfuseDownload = {
            guard let url = ExternalPlayerChoice.infuse.downloadURL else { return }
            NSWorkspace.shared.open(url)
        }
        mainWindowModel.onSelectPlayer = { [weak self] choice in
            guard let self else { return }
            self.libraryModel.setPlayer(choice, language: self.currentLanguage)
            self.refreshPlayerAvailability()
        }
        libraryModel.onPlayerChanged = { [weak self] _ in
            self?.refreshPlayerAvailability()
        }
        mainWindowModel.onRefreshStorage = { [weak self] in
            self?.refreshStorage()
        }
        mainWindowModel.onClearCache = { [weak self] in
            self?.clearTorrServerCache()
        }
        mainWindowModel.onCheckPort = { [weak self] in
            self?.checkTorrServerPort()
        }
        mainWindowModel.onFindTorrServer = { [weak self] in
            self?.findOtherTorrServerProcesses()
        }
        mainWindowModel.onRunFullDiagnostics = { [weak self] in
            self?.runFullDiagnostics()
        }
        mainWindowModel.onStopExternalProcesses = { [weak self] in
            self?.stopExternalTorrServerProcesses()
        }
        mainWindowModel.onCheckExecutable = { [weak self] in
            self?.checkTorrServerExecutable()
        }
        mainWindowModel.onCopyDiagnosticReport = { [weak self] in
            self?.copyDiagnosticReport()
        }
        mainWindowModel.onSaveDiagnosticReport = { [weak self] in
            self?.saveDiagnosticReport()
        }
        searchModel.onTorrentAdded = { [weak self] hash in
            self?.libraryModel.refresh(selectingHash: hash)
        }

        let hostingView = NSHostingView(
            rootView: ApplicationRootView(
                mainModel: mainWindowModel,
                libraryModel: libraryModel,
                searchModel: searchModel
            )
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let initialContentSize = NSSize(width: 1080, height: 680)
        serverContentSize = initialContentSize
        window.setContentSize(initialContentSize)
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.contentMaxSize = NSSize(width: 2400, height: 1600)
    }

    func resizeWindow(for section: AppSection) {
        _ = section
    }

    func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let aboutItem = appMenu.addItem(
            withTitle: texts.about,
            action: #selector(showAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: texts.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem(
            title: currentLanguage == .russian ? "Файл" : "File",
            action: nil,
            keyEquivalent: ""
        )
        let fileMenu = NSMenu(title: fileMenuItem.title)

        let addTorrentItem = fileMenu.addItem(
            withTitle: currentLanguage == .russian ? "Добавить torrent-файл…" : "Add Torrent File…",
            action: #selector(addTorrentFromMenu(_:)),
            keyEquivalent: "o"
        )
        addTorrentItem.target = self
        addTorrentItem.keyEquivalentModifierMask = [.command]

        let addMagnetItem = fileMenu.addItem(
            withTitle: currentLanguage == .russian ? "Добавить magnet-ссылку…" : "Add Magnet Link…",
            action: #selector(addMagnetFromMenu(_:)),
            keyEquivalent: "l"
        )
        addMagnetItem.target = self
        addMagnetItem.keyEquivalentModifierMask = [.command]

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem(
            title: texts.edit,
            action: nil,
            keyEquivalent: ""
        )
        let editMenu = NSMenu(title: texts.edit)

        let undoItem = editMenu.addItem(
            withTitle: texts.undo,
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]

        let redoItem = editMenu.addItem(
            withTitle: texts.redo,
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(.separator())

        let cutItem = editMenu.addItem(
            withTitle: texts.cut,
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        cutItem.keyEquivalentModifierMask = [.command]

        let copyItem = editMenu.addItem(
            withTitle: texts.copy,
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command]

        let pasteItem = editMenu.addItem(
            withTitle: texts.paste,
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = [.command]

        editMenu.addItem(.separator())

        let selectAllItem = editMenu.addItem(
            withTitle: texts.selectAll,
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = [.command]

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let navigateMenuItem = NSMenuItem(
            title: currentLanguage == .russian ? "Навигация" : "Navigate",
            action: nil,
            keyEquivalent: ""
        )
        let navigateMenu = NSMenu(title: navigateMenuItem.title)
        let searchItem = navigateMenu.addItem(
            withTitle: currentLanguage == .russian ? "Перейти к поиску" : "Go to Search",
            action: #selector(focusSearchFromMenu(_:)),
            keyEquivalent: "f"
        )
        searchItem.target = self
        searchItem.keyEquivalentModifierMask = [.command]
        navigateMenuItem.submenu = navigateMenu
        mainMenu.addItem(navigateMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

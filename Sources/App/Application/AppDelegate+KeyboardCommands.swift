import AppKit

@MainActor
extension AppDelegate {
    private var libraryCommandsAvailable: Bool {
        NSApp.keyWindow === window
            && mainWindowModel.selectedSection == .library
            && window?.attachedSheet == nil
            && !libraryModel.showsMagnetSheet
            && !libraryModel.showsPlayerSetup
            && libraryModel.pendingDeletionTorrents.isEmpty
            && libraryModel.alert == nil
    }

    // These selectors are fallback responders for the native Edit menu. Text
    // fields handle selectAll/copy/paste earlier in the responder chain.
    @objc func selectAll(_ sender: Any?) {
        guard libraryCommandsAvailable, mainWindowModel.canStop else { return }
        libraryModel.selectAllVisibleTorrents()
    }

    @objc func copy(_ sender: Any?) {
        guard libraryCommandsAvailable, let torrent = libraryModel.selectedTorrent else { return }
        libraryModel.copyStreamURL(for: torrent)
    }

    @objc func paste(_ sender: Any?) {
        guard libraryCommandsAvailable, mainWindowModel.canStop, !libraryModel.isAdding,
              let magnet = LibraryPasteboard.magnetLink(from: NSPasteboard.general.string(forType: .string)) else { return }
        libraryModel.magnetInput = magnet
        libraryModel.addMagnet(language: currentLanguage)
    }

    @objc func deselectLibraryItems(_ sender: Any?) {
        guard libraryCommandsAvailable else { return }
        libraryModel.clearSelection()
    }

    @objc func refreshCurrentPage(_ sender: Any?) {
        guard NSApp.keyWindow === window, window?.attachedSheet == nil else { return }
        switch mainWindowModel.selectedSection {
        case .library: libraryModel.refresh()
        case .search: searchModel.search(language: currentLanguage)
        }
    }

    @objc func showLibraryFromMenu(_ sender: Any?) {
        guard window?.attachedSheet == nil else { return }
        ensureWindowForCommand()
        mainWindowModel.selectedSection = .library
    }

    @objc func showSearchFromMenu(_ sender: Any?) {
        guard mainWindowModel.jackettEnabled, window?.attachedSheet == nil else { return }
        ensureWindowForCommand()
        mainWindowModel.selectedSection = .search
    }

    @objc func showLibraryList(_ sender: Any?) { changeLibraryDisplayMode(.compact) }
    @objc func showLibraryPosters(_ sender: Any?) { changeLibraryDisplayMode(.posters) }
    @objc func showLibraryCards(_ sender: Any?) { changeLibraryDisplayMode(.cards) }

    private func changeLibraryDisplayMode(_ mode: LibraryDisplayMode) {
        guard libraryCommandsAvailable else { return }
        libraryModel.setDisplayMode(mode)
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        showSettingsWindow(category: .keyboard)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectAll(_:)):
            return libraryCommandsAvailable && mainWindowModel.canStop && !libraryModel.filteredTorrents.isEmpty
        case #selector(copy(_:)):
            return libraryCommandsAvailable && libraryModel.selectedTorrent?.playableFiles.isEmpty == false
        case #selector(paste(_:)):
            return libraryCommandsAvailable && mainWindowModel.canStop && !libraryModel.isAdding
                && LibraryPasteboard.magnetLink(from: NSPasteboard.general.string(forType: .string)) != nil
        case #selector(deselectLibraryItems(_:)):
            return libraryCommandsAvailable && !libraryModel.selectedTorrentIDs.isEmpty
        case #selector(refreshCurrentPage(_:)):
            guard NSApp.keyWindow === window, window?.attachedSheet == nil else { return false }
            if mainWindowModel.selectedSection == .library {
                return mainWindowModel.canStop && !libraryModel.isRefreshing && libraryModel.alert == nil
            }
            return searchModel.isConfigured && !searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case #selector(showLibraryList(_:)), #selector(showLibraryPosters(_:)), #selector(showLibraryCards(_:)):
            return libraryCommandsAvailable
        case #selector(showSearchFromMenu(_:)):
            return mainWindowModel.jackettEnabled && window?.attachedSheet == nil
        case #selector(addTorrentFromMenu(_:)), #selector(addMagnetFromMenu(_:)):
            return mainWindowModel.canStop && !libraryModel.isAdding && window?.attachedSheet == nil
        default: return true
        }
    }
}

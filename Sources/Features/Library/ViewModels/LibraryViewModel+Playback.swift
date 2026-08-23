import AppKit
import Foundation
import UniformTypeIdentifiers

extension LibraryViewModel {
    func play(
        file: NativeTorrentFile,
        language: AppLanguage
    ) {
        guard let torrent = selectedTorrent else { return }
        play(torrent: torrent, file: file, using: playerChoice, language: language)
    }

    func playFirstFile(
        in torrent: NativeTorrent,
        using choice: ExternalPlayerChoice? = nil,
        language: AppLanguage
    ) {
        guard let file = torrent.playableFiles.first else { return }
        play(torrent: torrent, file: file, using: choice ?? playerChoice, language: language)
    }

    @discardableResult
    func playSelectedFirstFile(language: AppLanguage) -> Bool {
        guard let torrent = selectedTorrent,
              !torrent.playableFiles.isEmpty else {
            return false
        }
        playFirstFile(in: torrent, language: language)
        return true
    }

    func play(
        torrent: NativeTorrent,
        file: NativeTorrentFile,
        using choice: ExternalPlayerChoice,
        language: AppLanguage
    ) {
        guard let streamURL = api.streamURL(torrent: torrent, file: file) else { return }

        Task {
            await api.beginPreloading(
                torrentHash: torrent.hash,
                fileID: file.id
            )
        }

        do {
            try ExternalPlayerLauncher.open(
                streamURL,
                using: choice,
                customPlayerPath: customPlayerPath
            )
        } catch {
            alert = AppAlert(
                title: language == .russian
                    ? "Не удалось открыть плеер"
                    : "Could not open player",
                message: error.localizedDescription
            )
        }
    }

    func setPlayer(
        _ choice: ExternalPlayerChoice,
        language: AppLanguage
    ) {
        if choice == .custom {
            chooseCustomPlayer(language: language)
            return
        }

        playerChoice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: libraryPlayerKey)
        UserDefaults.standard.set(true, forKey: libraryPlayerSetupCompletedKey)
        showsPlayerSetup = false
        refreshDetectedPlayers()
        onPlayerChanged?(choice)
    }

    func dismissPlayerSetup() {
        UserDefaults.standard.set(true, forKey: libraryPlayerSetupCompletedKey)
        showsPlayerSetup = false
    }

    func download(_ choice: ExternalPlayerChoice) {
        guard let url = choice.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyStreamURL(for torrent: NativeTorrent) {
        guard
            let file = torrent.playableFiles.first,
            let url = api.streamURL(torrent: torrent, file: file)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func chooseCustomPlayer(language: AppLanguage) {
        let panel = NSOpenPanel()
        panel.title = language == .russian
            ? "Выберите медиаплеер"
            : "Choose media player"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        customPlayerPath = url.path
        playerChoice = .custom
        UserDefaults.standard.set(
            ExternalPlayerChoice.custom.rawValue,
            forKey: libraryPlayerKey
        )
        UserDefaults.standard.set(url.path, forKey: libraryCustomPlayerPathKey)
        UserDefaults.standard.set(true, forKey: libraryPlayerSetupCompletedKey)
        showsPlayerSetup = false
        onPlayerChanged?(.custom)
    }
}

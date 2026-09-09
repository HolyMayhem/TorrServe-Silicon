import AppKit
import Foundation
import UniformTypeIdentifiers

private let offlineDownloadDirectoryKey = "OfflineDownloadDirectory"

extension LibraryViewModel {
    func offlineDownloadFile(in torrent: NativeTorrent) -> NativeTorrentFile? {
        guard let currentSourceURL = offlineDownloadManager.currentRequest?.sourceURL else {
            return nil
        }
        return torrent.allFiles.first { file in
            api.streamURL(torrent: torrent, file: file) == currentSourceURL
        }
    }

    func chooseOfflineDownloadForFirstPlayableFile(
        in torrent: NativeTorrent,
        language: AppLanguage
    ) {
        guard let file = torrent.playableFiles.first else { return }
        chooseOfflineDownloadDestination(
            torrent: torrent,
            file: file,
            language: language
        )
    }

    func offlineDownloadIsUnavailable(for torrent: NativeTorrent) -> Bool {
        if offlineDownloadFile(in: torrent) != nil {
            return false
        }
        return offlineDownloadManager.state.isActive
            || offlineDownloadManager.state.resumableCheckpoint != nil
    }

    func offlineDownloadState(
        torrent: NativeTorrent,
        file: NativeTorrentFile
    ) -> OfflineDownloadState? {
        guard offlineDownloadMatches(torrent: torrent, file: file) else { return nil }
        return offlineDownloadManager.state
    }

    func offlineDownloadIsUnavailable(
        torrent: NativeTorrent,
        file: NativeTorrentFile
    ) -> Bool {
        guard !offlineDownloadMatches(torrent: torrent, file: file) else {
            return false
        }
        return offlineDownloadManager.state.isActive
            || offlineDownloadManager.state.resumableCheckpoint != nil
    }

    func chooseOfflineDownloadDestination(
        torrent: NativeTorrent,
        file: NativeTorrentFile,
        language: AppLanguage
    ) {
        let panel = NSSavePanel()
        panel.title = language == .russian
            ? "Сохранить для офлайн-просмотра"
            : "Save for Offline Viewing"
        panel.prompt = language == .russian ? "Скачать" : "Download"
        panel.nameFieldStringValue = file.displayName.isEmpty
            ? "TorrServe-download"
            : file.displayName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let contentType = UTType(filenameExtension: file.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.directoryURL = preferredOfflineDownloadDirectory()

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        UserDefaults.standard.set(
            destinationURL.deletingLastPathComponent().path,
            forKey: offlineDownloadDirectoryKey
        )
        startOfflineDownload(
            torrent: torrent,
            file: file,
            destinationURL: destinationURL,
            language: language
        )
    }

    @discardableResult
    func startOfflineDownload(
        torrent: NativeTorrent,
        file: NativeTorrentFile,
        destinationURL: URL,
        language: AppLanguage
    ) -> Bool {
        guard let sourceURL = api.streamURL(torrent: torrent, file: file) else {
            showOfflineDownloadError(
                language: language,
                message: language == .russian
                    ? "TorrServer не смог сформировать адрес файла."
                    : "TorrServer could not create the file URL."
            )
            return false
        }

        do {
            try offlineDownloadManager.start(OfflineDownloadRequest(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                expectedLength: file.length
            ))
            return true
        } catch {
            showOfflineDownloadError(
                language: language,
                message: error.localizedDescription
            )
            return false
        }
    }

    func pauseOfflineDownload() {
        offlineDownloadManager.pause()
    }

    func resumeOfflineDownload(language: AppLanguage) {
        do {
            try offlineDownloadManager.resume()
        } catch {
            showOfflineDownloadError(
                language: language,
                message: error.localizedDescription
            )
        }
    }

    func retryOfflineDownload(language: AppLanguage) {
        guard let request = offlineDownloadManager.currentRequest else { return }
        do {
            try offlineDownloadManager.start(request)
        } catch {
            showOfflineDownloadError(
                language: language,
                message: error.localizedDescription
            )
        }
    }

    func cancelOfflineDownload() {
        offlineDownloadManager.cancel()
    }

    func revealOfflineDownload() {
        guard case .completed(let url) = offlineDownloadManager.state else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func offlineDownloadMatches(
        torrent: NativeTorrent,
        file: NativeTorrentFile
    ) -> Bool {
        guard let currentSourceURL = offlineDownloadManager.currentRequest?.sourceURL,
              let sourceURL = api.streamURL(torrent: torrent, file: file) else {
            return false
        }
        return currentSourceURL == sourceURL
    }

    private func preferredOfflineDownloadDirectory() -> URL? {
        if let savedPath = UserDefaults.standard.string(
            forKey: offlineDownloadDirectoryKey
        ) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: savedPath,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                return URL(fileURLWithPath: savedPath, isDirectory: true)
            }
        }
        return FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first
    }

    private func showOfflineDownloadError(
        language: AppLanguage,
        message: String
    ) {
        alert = AppAlert(
            title: language == .russian
                ? "Не удалось скачать файл"
                : "Could Not Download File",
            message: message
        )
    }
}

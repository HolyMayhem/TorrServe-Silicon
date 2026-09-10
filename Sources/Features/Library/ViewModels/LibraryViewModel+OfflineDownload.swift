import AppKit
import Foundation

extension LibraryViewModel {
    func reconcileOfflineDownloads(in torrents: [NativeTorrent]) {
        for torrent in torrents {
            for file in torrent.playableFiles {
                guard let sourceURL = api.streamURL(torrent: torrent, file: file) else {
                    continue
                }
                offlineDownloadManager.reconcileCompletedDownload(
                    sourceURL: sourceURL,
                    filename: file.displayName,
                    expectedLength: file.length
                )
            }
        }
    }

    func offlineDownloadFile(in torrent: NativeTorrent) -> NativeTorrentFile? {
        guard let currentSourceURL = offlineDownloadManager.currentRequest?.sourceURL else {
            return nil
        }
        return torrent.allFiles.first { file in
            api.streamURL(torrent: torrent, file: file) == currentSourceURL
        }
    }

    func offlineDownloadedFile(in torrent: NativeTorrent) -> NativeTorrentFile? {
        torrent.playableFiles.first { file in
            guard let sourceURL = api.streamURL(torrent: torrent, file: file) else {
                return false
            }
            return offlineDownloadManager.completedDestination(
                sourceURL: sourceURL,
                expectedLength: file.length
            ) != nil
        }
    }

    func isTorrentDownloaded(_ torrent: NativeTorrent) -> Bool {
        offlineDownloadedFile(in: torrent) != nil
    }

    func downloadFirstPlayableFile(
        in torrent: NativeTorrent,
        language: AppLanguage
    ) {
        guard let file = torrent.playableFiles.first else { return }
        downloadOffline(
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
        if offlineDownloadMatches(torrent: torrent, file: file) {
            if case .completed = offlineDownloadManager.state {
                guard let sourceURL = api.streamURL(torrent: torrent, file: file),
                      let destinationURL = offlineDownloadManager.completedDestination(
                        sourceURL: sourceURL,
                        expectedLength: file.length
                      ) else {
                    return nil
                }
                return .completed(destinationURL)
            }
            return offlineDownloadManager.state
        }
        guard let sourceURL = api.streamURL(torrent: torrent, file: file),
              let destinationURL = offlineDownloadManager.completedDestination(
                sourceURL: sourceURL,
                expectedLength: file.length
              ) else {
            return nil
        }
        return .completed(destinationURL)
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

    func downloadOffline(
        torrent: NativeTorrent,
        file: NativeTorrentFile,
        language: AppLanguage
    ) {
        do {
            let destinationURL = try offlineDownloadManager.destinationURL(
                for: file.displayName
            )
            startOfflineDownload(
                torrent: torrent,
                file: file,
                destinationURL: destinationURL,
                language: language
            )
        } catch {
            showOfflineDownloadError(
                language: language,
                message: error.localizedDescription
            )
        }
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

    func revealOfflineDownload(
        torrent: NativeTorrent,
        file: NativeTorrentFile
    ) {
        guard let sourceURL = api.streamURL(torrent: torrent, file: file),
              let destinationURL = offlineDownloadManager.completedDestination(
                sourceURL: sourceURL,
                expectedLength: file.length
              ) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func deleteOfflineDownload(
        torrent: NativeTorrent,
        file: NativeTorrentFile,
        language: AppLanguage
    ) {
        guard let sourceURL = api.streamURL(torrent: torrent, file: file) else {
            return
        }

        do {
            try offlineDownloadManager.moveCompletedDownloadToTrash(
                sourceURL: sourceURL,
                expectedLength: file.length
            )
        } catch {
            alert = AppAlert(
                title: language == .russian
                    ? "Не удалось удалить файл"
                    : "Could Not Delete File",
                message: error.localizedDescription
            )
        }
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

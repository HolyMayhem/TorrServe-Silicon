import SwiftUI

struct CatalogPlaybackSheet: View {
    let torrent: NativeTorrent
    @ObservedObject var library: LibraryViewModel
    let text: CatalogText

    @Environment(\.dismiss) private var dismiss
    @State private var loadedTorrent: NativeTorrent?
    @State private var selectedFile: String?
    @State private var loadingFailed = false
    @State private var playbackError: String?
    @State private var retry = 0

    private var current: NativeTorrent { loadedTorrent ?? torrent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("Choose a file to play", "Выберите файл для воспроизведения")).font(.title2)
            Text(torrent.displayTitle).foregroundStyle(.secondary).lineLimit(2)

            if !current.playableFiles.isEmpty {
                List(current.playableFiles, id: \.stableID, selection: $selectedFile) { file in
                    HStack {
                        Text(file.displayName).lineLimit(1)
                        Spacer()
                        Text(SearchFormat.fileSize(file.length)).foregroundStyle(.secondary)
                    }
                    .tag(file.stableID)
                }
                .frame(minHeight: 140, maxHeight: 270)
            } else if loadingFailed {
                Label(text("No playable files are available yet.", "Файлы для воспроизведения пока недоступны."),
                      systemImage: "exclamationmark.circle")
                Button(text("Retry", "Повторить")) { retry += 1 }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(text("Waiting for TorrServer…", "Ожидание TorrServer…")).foregroundStyle(.secondary)
                }
            }
            if let playbackError {
                Text(playbackError).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(text("Close", "Закрыть")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(text("Play", "Воспроизвести")) {
                    guard let file = current.playableFiles.first(where: { $0.stableID == selectedFile }) else { return }
                    do {
                        try library.launchPlayback(torrent: current, file: file, using: library.playerChoice)
                        dismiss()
                    } catch {
                        playbackError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFile == nil)
            }
        }
        .padding(20)
        .frame(width: 500)
        .task(id: retry) { await loadFiles() }
    }

    private func loadFiles() async {
        loadingFailed = false
        if let file = current.playableFiles.first {
            selectedFile = file.stableID
            return
        }
        guard !torrent.hash.isEmpty else {
            loadingFailed = true
            return
        }
        for _ in 0..<10 {
            let refreshed = try? await library.api.torrent(hash: torrent.hash)
            guard !Task.isCancelled else { return }
            if let refreshed, let file = refreshed.playableFiles.first {
                loadedTorrent = refreshed
                selectedFile = file.stableID
                return
            }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
        }
        if !Task.isCancelled { loadingFailed = true }
    }
}

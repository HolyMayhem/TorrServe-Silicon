import AppKit
import SwiftUI

struct CompactLibraryHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CompactLibraryFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum LibraryKeyboardCommand: Equatable {
    case delete, play, paste, selectAll, deselectAll, copyStream, previous, next, escape

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        switch (keyCode, modifiers) {
        case (0, .command), (0, .control): return .selectAll
        case (0, [.command, .shift]): return .deselectAll
        case (8, .command): return .copyStream
        case (9, .command): return .paste
        case (51, []), (117, []): return .delete
        case (36, []), (76, []): return .play
        case (126, []): return .previous
        case (125, []): return .next
        case (53, []): return .escape
        default: return nil
        }
    }
}

struct LibraryKeyboardShortcutMonitor: NSViewRepresentable {
    let perform: (LibraryKeyboardCommand) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(perform: perform) }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.window = window
        }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.window = nsView.window
    }

    final class Coordinator {
        weak var window: NSWindow?
        var perform: (LibraryKeyboardCommand) -> Bool
        private var eventMonitor: Any?

        init(perform: @escaping (LibraryKeyboardCommand) -> Bool) {
            self.perform = perform
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, window.isKeyWindow,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSTextField),
                  let command = LibraryKeyboardCommand.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags)
            else { return event }
            return perform(command) ? nil : event
        }
    }

    final class WindowTrackingView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}

struct LibraryModePicker: View {
    @ObservedObject var model: LibraryViewModel
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 1) {
            ForEach(LibraryDisplayMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.setDisplayMode(mode)
                    }
                } label: {
                    Image(systemName: mode.systemImage)
                        .frame(width: 25, height: 23)
                        .background(
                            model.displayMode == mode
                                ? Color.accentColor.opacity(0.72)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.displayMode == mode ? Color.white : .secondary)
                .help(mode.title(language: language))
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct TorrentContextMenu: View {
    let torrent: NativeTorrent
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var offlineDownloadManager: OfflineDownloadManager
    let language: AppLanguage

    private var texts: LibraryTexts { LibraryTexts(language: language) }

    var body: some View {
        Button {
            model.playFirstFile(in: torrent, language: language)
        } label: {
            Label(texts.play, systemImage: "play.fill")
        }
        .disabled(torrent.playableFiles.isEmpty)

        Menu {
            ForEach(ExternalPlayerChoice.allCases) { choice in
                Button(choice.title(language: language)) {
                    model.playFirstFile(in: torrent, using: choice, language: language)
                }
            }
        } label: {
            Label(texts.openInAnotherPlayer, systemImage: "play.rectangle")
        }
        .disabled(torrent.playableFiles.isEmpty)

        offlineDownloadActions

        Button {
            model.copyStreamURL(for: torrent)
        } label: {
            Label(texts.copyStreamURL, systemImage: "link")
        }
        .disabled(torrent.playableFiles.isEmpty)

        Button {
            model.openSource(for: torrent)
        } label: {
            Label(texts.openSource, systemImage: "safari")
        }
        .disabled(model.metadata(for: torrent)?.sourceURL == nil)

        Divider()

        Button {
            model.showFiles(for: torrent)
        } label: {
            Label(texts.showFiles, systemImage: "list.bullet.rectangle")
        }

        Button {
            model.refreshMetadata(for: torrent)
        } label: {
            Label(texts.refreshMetadata, systemImage: "arrow.clockwise")
        }

        Divider()

        Button(role: .destructive) {
            model.requestRemoval(of: torrent)
        } label: {
            Label(texts.remove, systemImage: "trash")
        }
    }

    @ViewBuilder
    private var offlineDownloadActions: some View {
        if let offlineFile = model.offlineDownloadFile(in: torrent),
           let offlineState = model.offlineDownloadState(
            torrent: torrent,
            file: offlineFile
           ) {
            switch offlineState {
            case .queued:
                Button(texts.queuedDownload) {}
                    .disabled(true)
                cancelOfflineDownloadButton(for: offlineFile)
            case .preparing, .resuming:
                Button(texts.preparingDownload) {}
                    .disabled(true)
                cancelOfflineDownloadButton(for: offlineFile)
            case .downloading:
                Button {
                    model.pauseOfflineDownload()
                } label: {
                    Label(texts.pauseDownload, systemImage: "pause.fill")
                }
                cancelOfflineDownloadButton(for: offlineFile)
            case .pausing:
                Button(texts.pausingDownload) {}
                    .disabled(true)
                cancelOfflineDownloadButton(for: offlineFile)
            case .paused:
                Button {
                    model.resumeOfflineDownload(language: language)
                } label: {
                    Label(texts.resumeDownload, systemImage: "play.fill")
                }
                cancelOfflineDownloadButton(for: offlineFile)
            case .cancelling:
                Button(texts.cancellingDownload) {}
                    .disabled(true)
            case .completed:
                if let downloadedFile = model.offlineDownloadedFile(in: torrent) {
                    Button {
                        model.revealOfflineDownload(
                            torrent: torrent,
                            file: downloadedFile
                        )
                    } label: {
                        Label(texts.showInFinder, systemImage: "folder")
                    }
                } else {
                    startOfflineDownloadButton
                }
            case .failed(_, let checkpoint):
                if checkpoint != nil {
                    Button {
                        model.resumeOfflineDownload(language: language)
                    } label: {
                        Label(texts.resumeDownload, systemImage: "play.fill")
                    }
                    cancelOfflineDownloadButton(for: offlineFile)
                } else {
                    Button {
                        model.retryOfflineDownload(language: language)
                    } label: {
                        Label(texts.retryDownload, systemImage: "arrow.clockwise")
                    }
                }
            case .idle, .cancelled:
                startOfflineDownloadButton
            }
        } else if let downloadedFile = model.offlineDownloadedFile(in: torrent) {
            Button {
                model.revealOfflineDownload(
                    torrent: torrent,
                    file: downloadedFile
                )
            } label: {
                Label(texts.showInFinder, systemImage: "folder")
            }
        } else {
            startOfflineDownloadButton
        }
    }

    private var startOfflineDownloadButton: some View {
        Button {
            model.downloadFirstPlayableFile(
                in: torrent,
                language: language
            )
        } label: {
            Label(texts.downloadForOfflineViewing, systemImage: "arrow.down.to.line")
        }
        .disabled(
            torrent.playableFiles.isEmpty
                || model.offlineDownloadIsUnavailable(for: torrent)
        )
    }

    private func cancelOfflineDownloadButton(
        for file: NativeTorrentFile
    ) -> some View {
        Button(role: .destructive) {
            model.cancelOfflineDownload(torrent: torrent, file: file)
        } label: {
            Label(texts.cancelDownload, systemImage: "xmark")
        }
    }
}

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

struct LibraryKeyboardShortcutMonitor: NSViewRepresentable {
    let onDelete: () -> Bool
    let onReturn: () -> Bool
    let onPaste: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDelete: onDelete,
            onReturn: onReturn,
            onPaste: onPaste
        )
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.window = window
        }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.onDelete = onDelete
        context.coordinator.onReturn = onReturn
        context.coordinator.onPaste = onPaste
        context.coordinator.window = nsView.window
    }

    final class Coordinator {
        weak var window: NSWindow?
        var onDelete: () -> Bool
        var onReturn: () -> Bool
        var onPaste: () -> Bool
        private var eventMonitor: Any? = nil

        init(
            onDelete: @escaping () -> Bool,
            onReturn: @escaping () -> Bool,
            onPaste: @escaping () -> Bool
        ) {
            self.onDelete = onDelete
            self.onReturn = onReturn
            self.onPaste = onPaste
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window,
                  !isEditingText(in: event.window)
            else {
                return event
            }

            if Self.isPasteShortcut(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
            ) {
                return onPaste() ? nil : event
            }

            guard event.modifierFlags.intersection([
                .command,
                .control,
                .option
            ]).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 51, 117:
                return onDelete() ? nil : event
            case 36, 76:
                return onReturn() ? nil : event
            default:
                return event
            }
        }

        static func isPasteShortcut(
            keyCode: UInt16,
            modifierFlags: NSEvent.ModifierFlags
        ) -> Bool {
            let relevantModifiers = modifierFlags.intersection([
                .command,
                .control,
                .option,
                .shift
            ])
            return keyCode == 9 && relevantModifiers == .command
        }

        private func isEditingText(in window: NSWindow?) -> Bool {
            window?.firstResponder is NSTextView
                || window?.firstResponder is NSTextField
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
}

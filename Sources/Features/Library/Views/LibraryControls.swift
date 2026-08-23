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

struct LibraryScrollContentMask: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let fadeLength: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, topInset - fadeLength))

            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(fadeLength, topInset))

            Color.black
                .frame(maxHeight: .infinity)

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.56), location: 0.24),
                    .init(color: .black.opacity(0.12), location: 0.52),
                    .init(color: .black.opacity(0.035), location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bottomInset)
        }
        .accessibilityHidden(true)
    }
}

struct LibraryScrollMetrics: Equatable {
    static let zero = LibraryScrollMetrics(
        contentOffsetY: 0,
        contentHeight: 0,
        containerHeight: 0
    )

    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat

    init(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat
    ) {
        self.contentOffsetY = contentOffsetY
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
    }

    init(_ geometry: ScrollGeometry) {
        contentOffsetY = geometry.contentOffset.y
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
    }
}

struct LibraryScrollIndicator: View {
    let metrics: LibraryScrollMetrics
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = max(0, proxy.size.height - topInset - bottomInset)
            let contentHeight = max(metrics.contentHeight, 1)
            let viewportRatio = min(1, metrics.containerHeight / contentHeight)
            let thumbHeight = min(trackHeight, max(28, trackHeight * viewportRatio))
            let maximumOffset = max(1, metrics.contentHeight - metrics.containerHeight)
            let progress = min(1, max(0, metrics.contentOffsetY / maximumOffset))
            let thumbTravel = max(0, trackHeight - thumbHeight)

            Capsule()
                .fill(Color.secondary.opacity(0.72))
                .frame(width: 3, height: thumbHeight)
                .position(
                    x: proxy.size.width - 4,
                    y: topInset + thumbHeight / 2 + thumbTravel * progress
                )
                .opacity(
                    isVisible && metrics.contentHeight > metrics.containerHeight
                        ? 1
                        : 0
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LibraryNativeScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.scheduleUpdates()
        return view
    }

    func updateNSView(_ nsView: LocatorView, context: Context) {
        nsView.scheduleUpdates()
    }

    final class LocatorView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleUpdates()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdates()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func scheduleUpdates() {
            configureNearestScrollView()
            for delay in [0.03, 0.12, 0.35] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.configureNearestScrollView()
                }
            }
        }

        private func configureNearestScrollView() {
            guard let window, let contentView = window.contentView else { return }
            let locatorFrame = convert(bounds, to: nil)
            let locatorCenter = CGPoint(x: locatorFrame.midX, y: locatorFrame.midY)

            let candidate = contentView.descendantScrollViews
                .filter { scrollView in
                    let frame = scrollView.convert(scrollView.bounds, to: nil)
                    return frame.contains(locatorCenter)
                }
                .min { left, right in
                    let leftFrame = left.convert(left.bounds, to: nil)
                    let rightFrame = right.convert(right.bounds, to: nil)
                    return Self.frameDistance(leftFrame, locatorFrame)
                        < Self.frameDistance(rightFrame, locatorFrame)
                }

            guard let candidate else { return }
            candidate.hasVerticalScroller = false
            candidate.verticalScroller?.removeFromSuperview()
            candidate.verticalScroller = nil
            candidate.tile()
            candidate.needsLayout = true
            candidate.layoutSubtreeIfNeeded()
        }

        private static func frameDistance(_ left: CGRect, _ right: CGRect) -> CGFloat {
            abs(left.minX - right.minX)
                + abs(left.minY - right.minY)
                + abs(left.width - right.width)
                + abs(left.height - right.height)
        }
    }
}

private extension NSView {
    var descendantScrollViews: [NSScrollView] {
        subviews.flatMap { child in
            (child as? NSScrollView).map { [$0] } ?? child.descendantScrollViews
        }
    }
}

struct LibraryKeyboardShortcutMonitor: NSViewRepresentable {
    let onDelete: () -> Bool
    let onReturn: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onDelete: onDelete, onReturn: onReturn)
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
        context.coordinator.window = nsView.window
    }

    final class Coordinator {
        weak var window: NSWindow?
        var onDelete: () -> Bool
        var onReturn: () -> Bool
        private var eventMonitor: Any? = nil

        init(onDelete: @escaping () -> Bool, onReturn: @escaping () -> Bool) {
            self.onDelete = onDelete
            self.onReturn = onReturn
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
                  !isEditingText(in: event.window),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            else {
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

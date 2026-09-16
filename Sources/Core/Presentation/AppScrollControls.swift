import AppKit
import SwiftUI

struct AppScrollContentMask: View {
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

struct AppScrollMetrics: Equatable {
    static let zero = AppScrollMetrics(
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

struct AppScrollIndicator: View {
    let metrics: AppScrollMetrics
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

struct AppNativeScrollIndicatorHider: NSViewRepresentable {
    static func removeReservedVerticalScrollerSpace(from scrollView: NSScrollView) {
        // With the macOS legacy scroller style, AppKit reserves a full-width
        // trailing gutter before SwiftUI hides the native indicator. Switching
        // to overlay first guarantees that no content width is consumed. Keep
        // this operation idempotent because SwiftUI may restore the native
        // scroller after replacing or relaying out its internal NSScrollView.
        var needsRetile = false

        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
            needsRetile = true
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
            needsRetile = true
        }
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
            needsRetile = true
        }
        if let verticalScroller = scrollView.verticalScroller {
            verticalScroller.removeFromSuperview()
            scrollView.verticalScroller = nil
            needsRetile = true
        }

        guard needsRetile else { return }
        scrollView.tile()
        scrollView.needsLayout = true
    }

    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.scheduleUpdates()
        return view
    }

    func updateNSView(_ nsView: LocatorView, context: Context) {
        nsView.scheduleUpdates()
    }

    final class LocatorView: NSView {
        private var windowUpdateObserver: NSObjectProtocol?
        private var updateIsScheduled = false

        deinit {
            if let windowUpdateObserver {
                NotificationCenter.default.removeObserver(windowUpdateObserver)
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleUpdates()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if let windowUpdateObserver {
                NotificationCenter.default.removeObserver(windowUpdateObserver)
                self.windowUpdateObserver = nil
            }

            if let window {
                windowUpdateObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.maintainEnclosingScrollView()
                }
            }

            scheduleUpdates()
        }

        override func layout() {
            super.layout()
            scheduleImmediateUpdate()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func scheduleUpdates() {
            maintainEnclosingScrollView()
            for delay in [0.03, 0.12, 0.35] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.maintainEnclosingScrollView()
                }
            }
        }

        private func scheduleImmediateUpdate() {
            guard !updateIsScheduled else { return }
            updateIsScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateIsScheduled = false
                self.maintainEnclosingScrollView()
            }
        }

        private func maintainEnclosingScrollView() {
            // The locator is mounted in the ScrollView's content, so AppKit can
            // resolve its exact owner through the view hierarchy. Do not scan
            // the window by coordinates: animated SwiftUI transitions may keep
            // the outgoing and incoming scroll views alive at the same frame.
            guard let enclosingScrollView else { return }
            AppNativeScrollIndicatorHider
                .removeReservedVerticalScrollerSpace(from: enclosingScrollView)
        }
    }
}

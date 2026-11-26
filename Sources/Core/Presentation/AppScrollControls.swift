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
    static let zero = AppScrollMetrics()

    var offset: CGFloat = 0
    var contentLength: CGFloat = 0
    var containerLength: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry, axis: Axis = .vertical) {
        switch axis {
        case .vertical:
            offset = geometry.contentOffset.y
            contentLength = geometry.contentSize.height
            containerLength = geometry.containerSize.height
        case .horizontal:
            offset = geometry.contentOffset.x
            contentLength = geometry.contentSize.width
            containerLength = geometry.containerSize.width
        }
    }
}

struct AppScrollIndicator: View {
    let metrics: AppScrollMetrics
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isVisible: Bool
    var axis: Axis = .vertical

    var body: some View {
        GeometryReader { proxy in
            let vertical = axis == .vertical
            let length = vertical ? proxy.size.height : proxy.size.width
            let trackLength = max(0, length - topInset - bottomInset)
            let viewportRatio = min(1, metrics.containerLength / max(metrics.contentLength, 1))
            let thumbLength = min(trackLength, max(28, trackLength * viewportRatio))
            let maximumOffset = max(1, metrics.contentLength - metrics.containerLength)
            let progress = min(1, max(0, metrics.offset / maximumOffset))
            let center = topInset + thumbLength / 2 + (trackLength - thumbLength) * progress

            Capsule()
                .fill(Color.secondary.opacity(0.72))
                .frame(width: vertical ? 3 : thumbLength, height: vertical ? thumbLength : 3)
                .position(
                    x: vertical ? proxy.size.width - 4 : center,
                    y: vertical ? center : proxy.size.height - 4
                )
                .opacity(isVisible && metrics.contentLength > metrics.containerLength ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AppNativeScrollIndicatorHider: NSViewRepresentable {
    var axis: Axis = .vertical

    private static func hideScroller(_ axis: Axis, in scrollView: NSScrollView) {
        // With the macOS legacy scroller style, AppKit reserves a full-width
        // gutter before SwiftUI hides the native indicator. Switching
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
        let hasScroller = axis == .vertical ? \.hasVerticalScroller : \NSScrollView.hasHorizontalScroller
        let scroller = axis == .vertical ? \.verticalScroller : \NSScrollView.horizontalScroller
        if scrollView[keyPath: hasScroller] {
            scrollView[keyPath: hasScroller] = false
            needsRetile = true
        }
        if let nativeScroller = scrollView[keyPath: scroller] {
            nativeScroller.removeFromSuperview()
            scrollView[keyPath: scroller] = nil
            needsRetile = true
        }

        guard needsRetile else { return }
        scrollView.tile()
        scrollView.needsLayout = true
    }

    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.axis = axis
        view.scheduleUpdates()
        return view
    }

    func updateNSView(_ nsView: LocatorView, context: Context) {
        nsView.axis = axis
        nsView.scheduleUpdates()
    }

    final class LocatorView: NSView {
        var axis: Axis = .vertical
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
            AppNativeScrollIndicatorHider.hideScroller(axis, in: enclosingScrollView)
        }
    }
}

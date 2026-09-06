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
        // to overlay first guarantees that no content width is consumed even
        // if SwiftUI briefly recreates the scroller during layout.
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = false
        scrollView.verticalScroller?.removeFromSuperview()
        scrollView.verticalScroller = nil
        scrollView.tile()
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
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
            AppNativeScrollIndicatorHider
                .removeReservedVerticalScrollerSpace(from: candidate)
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

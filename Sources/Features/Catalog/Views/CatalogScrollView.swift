import SwiftUI

struct CatalogScrollView<Content: View>: View {
    var axis: Axis = .vertical
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metrics = AppScrollMetrics.zero
    @State private var showsIndicator = false
    private let fadeLength: CGFloat = 18

    private var leadingFade: Double {
        Double(min(1, max(0, metrics.offset) / fadeLength))
    }

    private var trailingFade: Double {
        guard axis == .horizontal else { return 0 }
        let remaining = metrics.contentLength - metrics.containerLength - max(0, metrics.offset)
        return Double(min(1, max(0, remaining) / fadeLength))
    }

    var body: some View {
        ScrollView(axis == .vertical ? .vertical : .horizontal) {
            content()
                .padding(.bottom, axis == .horizontal ? 8 : 0)
                .background { AppNativeScrollIndicatorHider(axis: axis) }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: AppScrollMetrics.self) { geometry in
            AppScrollMetrics(geometry, axis: axis)
        } action: { _, newMetrics in
            metrics = newMetrics
        }
        .onScrollPhaseChange { _, phase in
            withAnimation(reduceMotion ? nil : .easeOut(duration: phase.isScrolling ? 0.08 : 0.24)) {
                showsIndicator = phase.isScrolling
            }
        }
        .mask {
            GeometryReader { proxy in
                let length = axis == .vertical ? proxy.size.height : proxy.size.width
                let edge = min(0.5, fadeLength / max(1, length))
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(1 - leadingFade), location: 0),
                        .init(color: .black, location: edge),
                        .init(color: .black, location: 1 - edge),
                        .init(color: .black.opacity(1 - trailingFade), location: 1)
                    ],
                    startPoint: axis == .vertical ? .top : .leading,
                    endPoint: axis == .vertical ? .bottom : .trailing
                )
            }
        }
        .overlay(alignment: axis == .vertical ? .top : .leading) {
            edgeBlur(from: axis == .vertical ? .top : .leading,
                     to: axis == .vertical ? .bottom : .trailing, opacity: leadingFade)
        }
        .overlay(alignment: .trailing) {
            if axis == .horizontal {
                edgeBlur(from: .trailing, to: .leading, opacity: trailingFade)
            }
        }
        .overlay {
            AppScrollIndicator(metrics: metrics, topInset: 0, bottomInset: 0, isVisible: showsIndicator, axis: axis)
        }
    }

    private func edgeBlur(from edge: UnitPoint, to interior: UnitPoint, opacity: Double) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(width: axis == .horizontal ? fadeLength : nil, height: axis == .vertical ? fadeLength : nil)
            .mask {
                LinearGradient(colors: [.black, .clear], startPoint: edge, endPoint: interior)
            }
            .opacity(opacity * 0.65)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassPanel(
        cornerRadius: CGFloat = 12,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            if interactive {
                self
                    .background(Color.primary.opacity(0.025), in: shape)
                    .glassEffect(.regular.interactive(), in: shape)
            } else {
                self
                    .background(Color.primary.opacity(0.025), in: shape)
                    .glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func liquidGlassControl() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func liquidGlassProminentControl() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

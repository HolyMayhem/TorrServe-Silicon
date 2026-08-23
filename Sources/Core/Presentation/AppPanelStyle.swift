import SwiftUI

extension View {
    @ViewBuilder
    func appPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

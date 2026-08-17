import SwiftUI

struct LiquidGlassToggleStyle: ToggleStyle {
    private let width: CGFloat
    private let height: CGFloat

    init(width: CGFloat = 44, height: CGFloat = 25) {
        self.width = width
        self.height = height
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.24)) {
                configuration.isOn.toggle()
            }
        } label: {
            LiquidGlassToggleBody(
                isOn: configuration.isOn,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct LiquidGlassToggleBody: View {
    let isOn: Bool
    let width: CGFloat
    let height: CGFloat

    private var inset: CGFloat { 3 }
    private var thumbSize: CGFloat { height - inset * 2 }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            toggleTrack

            toggleThumb
                .padding(inset)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .animation(.smooth(duration: 0.24), value: isOn)
    }

    @ViewBuilder
    private var toggleTrack: some View {
        let shape = Capsule()
        let tint = isOn ? Color.accentColor : Color.secondary

        if #available(macOS 26.0, *) {
            shape
                .fill(tint.opacity(isOn ? 0.30 : 0.10))
                .glassEffect(
                    .regular.tint(tint.opacity(isOn ? 0.44 : 0.08)).interactive(),
                    in: shape
                )
        } else {
            shape
                .fill(tint.opacity(isOn ? 0.62 : 0.20))
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var toggleThumb: some View {
        let thumb = Circle()
            .fill(.white.opacity(0.94))
            .frame(width: thumbSize, height: thumbSize)

        if #available(macOS 26.0, *) {
            thumb
                .glassEffect(
                    .regular.tint(.white.opacity(0.24)).interactive(),
                    in: Circle()
                )
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        } else {
            thumb.shadow(color: .black.opacity(0.24), radius: 2, y: 1)
        }
    }
}

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

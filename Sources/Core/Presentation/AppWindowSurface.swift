import AppKit
import SwiftUI

/// Use the system window/sidebar materials, including wallpaper tint, appearance
/// changes and reduced transparency. Opaque NSColor fills hide these materials.
struct AppWindowSurface: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A single size and surface for the search field and its adjacent controls.
enum AppToolbarMetrics {
    static let controlHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 8
}

private struct AppToolbarControlSurface: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .frame(height: AppToolbarMetrics.controlHeight)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(
                Color.primary.opacity(isEnabled ? 0.065 : 0.035),
                in: RoundedRectangle(cornerRadius: AppToolbarMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppToolbarMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppToolbarMetrics.cornerRadius, style: .continuous))
    }
}

extension View {
    func appToolbarControlSurface() -> some View { modifier(AppToolbarControlSurface()) }
}

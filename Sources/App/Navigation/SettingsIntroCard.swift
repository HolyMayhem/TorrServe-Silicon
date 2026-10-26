import AppKit
import SwiftUI

enum SettingsScreenLayout {
    static let contentMaxWidth: CGFloat = 740
    static let formContentInset: CGFloat = 20
    static let horizontalPadding: CGFloat = 0
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 0
    static let sectionSpacing: CGFloat = 20
    static let scrollContentTopPadding: CGFloat = 20
    static let collapsedHeaderLeadingPadding: CGFloat = 180
}

private struct SettingsSidebarVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var settingsSidebarIsVisible: Bool {
        get { self[SettingsSidebarVisibilityKey.self] }
        set { self[SettingsSidebarVisibilityKey.self] = newValue }
    }
}

enum SettingsVisualStyle {
    static var windowBackgroundNSColor: NSColor { .clear }
    static var windowBackground: some View { AppWindowSurface().ignoresSafeArea() }
    static var sidebarBackground: some View { AppWindowSurface(material: .sidebar).ignoresSafeArea() }
    static var sidebarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    private static let panelFill = NSColor(name: "TorrServeSettingsGroup") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.white.withAlphaComponent(dark ? 0.035 : 0.65)
    }
    static var panelBackground: Color { Color(nsColor: panelFill) }
}

struct SettingsPageHeader: View {
    let title: String
    let message: String
    var isSettingsPage = false
    static let height: CGFloat = 48
    @Environment(\.settingsSidebarIsVisible) private var isSidebarVisible

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height, alignment: .center)
        .padding(.leading, isSidebarVisible
            ? 18
            : SettingsScreenLayout.collapsedHeaderLeadingPadding)
        .padding(.trailing, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: isSidebarVisible)
        .accessibilityElement(children: .combine)
    }
}

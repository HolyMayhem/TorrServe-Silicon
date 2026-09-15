import AppKit
import SwiftUI

enum SettingsScreenLayout {
    static let contentMaxWidth: CGFloat = .infinity
    static let formContentInset: CGFloat = 14
    static let horizontalPadding: CGFloat = 0
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 0
    static let sectionSpacing: CGFloat = 14
    static let scrollContentTopPadding: CGFloat = 14
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
    static var windowBackgroundNSColor: NSColor {
        adaptiveColor(
            dark: NSColor(
                srgbRed: 31.0 / 255.0,
                green: 33.0 / 255.0,
                blue: 47.0 / 255.0,
                alpha: 1
            ),
            light: .windowBackgroundColor
        )
    }

    static var windowBackground: Color {
        Color(nsColor: windowBackgroundNSColor)
    }

    static var sidebarBackground: Color {
        Color(nsColor: adaptiveColor(
            dark: NSColor(
                srgbRed: 28.0 / 255.0,
                green: 30.0 / 255.0,
                blue: 43.0 / 255.0,
                alpha: 1
            ),
            light: .windowBackgroundColor
        ))
    }

    static var panelBackground: Color {
        Color(nsColor: adaptiveColor(
            dark: NSColor(
                srgbRed: 38.0 / 255.0,
                green: 40.0 / 255.0,
                blue: 54.0 / 255.0,
                alpha: 1
            ),
            light: .controlBackgroundColor
        ))
    }

    private static func adaptiveColor(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

struct SettingsPageHeader: View {
    let title: String
    let message: String
    @Environment(\.settingsSidebarIsVisible) private var isSidebarVisible

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)
        .padding(.leading, isSidebarVisible
            ? 18
            : SettingsScreenLayout.collapsedHeaderLeadingPadding)
        .padding(.trailing, 18)
        .background(SettingsVisualStyle.windowBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: isSidebarVisible)
        .accessibilityElement(children: .combine)
    }
}

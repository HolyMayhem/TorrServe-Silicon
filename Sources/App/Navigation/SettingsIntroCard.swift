import AppKit
import SwiftUI

enum SettingsScreenLayout {
    static let contentMaxWidth: CGFloat = .infinity
    static let formContentInset: CGFloat = 20
    static let horizontalPadding: CGFloat = 0
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 0
    static let sectionSpacing: CGFloat = 12
    static let scrollContentTopPadding: CGFloat = 30
}

enum SettingsVisualStyle {
    static var panelBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(
                    srgbRed: 37.0 / 255.0,
                    green: 40.0 / 255.0,
                    blue: 51.0 / 255.0,
                    alpha: 1
                )
            }
            return .controlBackgroundColor
        })
    }
}

struct SettingsScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}

struct SettingsScrollEdgeFade: View {
    var body: some View {
        SettingsBackdropBlur()
            .mask {
                LinearGradient(
                    colors: [.black, .black.opacity(0.86), .black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 34)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SettingsBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .headerView
        nsView.blendingMode = .withinWindow
        nsView.state = .active
    }
}

extension View {
    func settingsScrollEdgeFade() -> some View {
        overlay(alignment: .top) {
            SettingsScrollEdgeFade()
        }
    }
}

struct SettingsIntroCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var usesContainerBackground = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            if usesContainerBackground {
                Color.secondary.opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .overlay {
            if usesContainerBackground {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

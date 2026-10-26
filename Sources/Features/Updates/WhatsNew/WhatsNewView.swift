import AppKit
import SwiftUI

struct WhatsNewView: View {
    let manifest: WhatsNewManifest
    let languageCode: String
    let appVersion: String
    let onContinue: () -> Void
    let onShowDetails: () -> Void
    private var content: WhatsNewManifest.Content { manifest.content(languageCode: languageCode) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 50)
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
                Text(content.title)
                    .font(.system(size: 27, weight: .semibold))
                    .padding(.bottom, 9)
                Text("TorrServe Silicon · \(languageCode == "ru" ? "Версия" : "Version") \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 50)
            .padding(.bottom, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(content.features.enumerated()), id: \.offset) { _, feature in
                        HStack(alignment: .top, spacing: 17) {
                            Image(systemName: NSImage(systemSymbolName: feature.symbol, accessibilityDescription: nil) == nil ? "sparkles" : feature.symbol)
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 34, height: 37)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(feature.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(feature.body)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)

            VStack(spacing: 13) {
                Button(content.continueTitle, action: onContinue)
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .clipShape(Capsule())
                    .keyboardShortcut(.defaultAction)
                if manifest.detailsURL != nil {
                    Button(content.detailsTitle, action: onShowDetails)
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 38)
        .frame(width: 520, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

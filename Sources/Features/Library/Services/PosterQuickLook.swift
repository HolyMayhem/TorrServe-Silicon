import QuickLook
import SwiftUI

private struct PosterQuickLookModifier: ViewModifier {
    let url: URL?
    let title: String

    @State private var previewURL: URL?
    @State private var isPreparing = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded(openPreview))
            .overlay {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .quickLookPreview($previewURL)
            .accessibilityAddTraits(url == nil ? [] : .isButton)
            .accessibilityLabel(title)
    }

    private func openPreview() {
        guard let url, !isPreparing else { return }
        isPreparing = true
        Task { @MainActor in
            defer { isPreparing = false }
            previewURL = try? await ImageCache.shared.previewURL(
                for: url,
                title: title
            )
        }
    }
}

extension View {
    func posterQuickLook(url: URL?, title: String) -> some View {
        modifier(PosterQuickLookModifier(url: url, title: title))
    }
}

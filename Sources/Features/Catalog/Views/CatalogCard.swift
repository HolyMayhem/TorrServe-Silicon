import SwiftUI

struct CatalogPoster: View {
    let url: URL?

    @Environment(\.catalogImageMirror) private var mirror
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: CatalogImageCache.Artwork?

    var body: some View {
        Color.primary.opacity(0.06)
            .overlay {
                if let artwork {
                    Image(decorative: artwork.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: artwork != nil)
            .task(id: ImageRequest(url: url, mirror: mirror)) {
                artwork = nil
                guard let url else { return }
                let result = try? await CatalogImageCache.shared.artwork(for: url, mirror: mirror)
                if !Task.isCancelled { artwork = result }
            }
    }

    private struct ImageRequest: Hashable {
        let url: URL?
        let mirror: URL?
    }
}

private struct CatalogImageMirrorKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

extension EnvironmentValues {
    var catalogImageMirror: URL? {
        get { self[CatalogImageMirrorKey.self] }
        set { self[CatalogImageMirrorKey.self] = newValue }
    }
}

struct CatalogCard: View {
    let item: CatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CatalogPoster(url: item.poster)
                .aspectRatio(2.0 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
            Text(item.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            HStack {
                Text(item.year.map { String($0) } ?? "—")
                Spacer(minLength: 4)
                if item.rating > 0 {
                    Label(item.rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(item.title)
    }
}

struct CatalogSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .aspectRatio(2.0 / 3, contentMode: .fit)
            RoundedRectangle(cornerRadius: 3).frame(width: 82, height: 12)
            RoundedRectangle(cornerRadius: 3).frame(width: 50, height: 10)
        }
        .foregroundStyle(Color.primary.opacity(0.08))
        .accessibilityHidden(true)
    }
}

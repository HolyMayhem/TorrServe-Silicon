import SwiftUI

struct OfflineMediaArtwork: View {
    let group: OfflineMediaGroup

    var body: some View {
        CachedRemoteImage(
            url: group.posterURL.flatMap { URL(string: $0) },
            contentMode: .fill,
            placeholderSystemImage: group.isSeries ? "tv" : "film"
        )
        .clipped()
    }
}

struct OfflineMediaCard: View {
    let group: OfflineMediaGroup
    let mode: LibraryDisplayMode
    let language: AppLanguage
    var isSelected = false
    let open: () -> Void

    private var isRussian: Bool { language == .russian }
    private var description: String {
        let kind = group.isSeries ? (isRussian ? "Сериал" : "Series") : (isRussian ? "Фильм" : "Movie")
        return "\(kind) · \(isRussian ? "Файлов" : "Files"): \(group.records.count)"
    }

    var body: some View {
        Button(action: open) {
            Group {
                switch mode {
                case .compact: compactRow
                case .posters: posterCard
                case .cards: wideCard
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(mode == .compact ? 0 : 0.07),
            in: RoundedRectangle(cornerRadius: mode == .compact ? 12 : 16)
        )
        .accessibilityLabel("\(group.title), \(description)")
        .help(isRussian ? "Открыть файлы" : "Open files")
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            OfflineMediaArtwork(group: group)
                .frame(width: 42, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 5) {
                Text(group.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                Text(description).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var posterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    GeometryReader { bounds in
                        OfflineMediaArtwork(group: group)
                            .frame(width: bounds.size.width, height: bounds.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(group.title)
                .font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                .frame(height: 32, alignment: .topLeading)
            Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wideCard: some View {
        HStack(spacing: 18) {
            OfflineMediaArtwork(group: group)
                .frame(width: 96, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Text(group.title).font(.title3.weight(.semibold)).lineLimit(2)
                Text(description).font(.callout).foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label(isRussian ? "Открыть файлы" : "Open files", systemImage: "chevron.right")
                    .font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

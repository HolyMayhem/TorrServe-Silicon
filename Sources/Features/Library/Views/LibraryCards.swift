import AppKit
import SwiftUI

struct TorrentPosterCard: View {
    let torrent: NativeTorrent
    let metadata: LibraryMetadata?
    let language: AppLanguage
    let isSelected: Bool
    let select: () -> Void
    let play: () -> Void

    private var texts: LibraryTexts { LibraryTexts(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                LibraryPoster(torrent: torrent, metadata: metadata)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(spacing: 7) {
                    HStack {
                        Text(texts.status(for: torrent))
                            .font(.caption2.weight(.semibold))
                        Spacer()
                        if let resolution = torrent.resolutionLabel {
                            Text(resolution).font(.caption2.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)

                    if torrent.stat == 2, let progress = torrent.bufferingProgress {
                        ProgressView(value: progress)
                            .tint(.orange)
                    }

                    Button(action: play) {
                        Label(texts.watch, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(torrent.playableFiles.isEmpty)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(metadata?.displayTitle ?? torrent.displayTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)

            HStack {
                Text(LibraryFormat.fileSize(torrent.torrentSize))
                Spacer()
                if let year = metadata?.releaseDate?.prefix(4), !year.isEmpty {
                    Text(String(year))
                }
                if let rating = metadata?.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: select)
    }
}

struct TorrentLargeCard: View {
    let torrent: NativeTorrent
    let metadata: LibraryMetadata?
    let language: AppLanguage
    let translationMode: OverviewTranslationMode
    let isSelected: Bool
    let select: () -> Void
    let play: () -> Void

    private var texts: LibraryTexts { LibraryTexts(language: language) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            LibraryPoster(torrent: torrent, metadata: metadata)
                .frame(width: 112, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Text(metadata?.displayTitle ?? torrent.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Spacer()
                    if let resolution = torrent.resolutionLabel {
                        Text(resolution)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
                }

                if let summary = metadata?.summary, !summary.isEmpty {
                    LocalizedOverviewText(
                        sourceText: summary,
                        provider: metadata?.metadataProvider,
                        mediaID: metadata?.metadataProviderID,
                        language: language,
                        translationMode: translationMode,
                        lineLimit: 4
                    )
                }

                if let metadata {
                    HStack(spacing: 7) {
                        if let releaseDate = metadata.releaseDate, !releaseDate.isEmpty {
                            Text(releaseDate)
                        }
                        if let runtime = metadata.runtimeMinutes, runtime > 0 {
                            Text("\(runtime) min")
                        }
                        if let rating = metadata.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label("\(texts.seeds) \(torrent.connectedSeeders)", systemImage: "arrow.up.circle")
                    Label("\(texts.peers) \(max(torrent.activePeers, torrent.totalPeers))", systemImage: "person.2")
                    Label(LibraryFormat.speed(torrent.downloadSpeed), systemImage: "arrow.down.circle")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                if torrent.stat == 2, let progress = torrent.bufferingProgress {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(texts.buffering)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        ProgressView(value: progress).tint(.orange)
                    }
                }

                Spacer()

                HStack {
                    Text(LibraryFormat.fileSize(torrent.torrentSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: play) {
                        Label(texts.watch, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(torrent.playableFiles.isEmpty)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07)
                if let value = metadata?.backdropURL,
                   let url = URL(string: value),
                   !value.isEmpty {
                    CachedRemoteImage(
                        url: url,
                        contentMode: .fill,
                        placeholderSystemImage: "photo"
                    )
                    .opacity(0.14)
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor).opacity(0.35),
                            Color(nsColor: .windowBackgroundColor).opacity(0.82)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .clipShape(shape)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: select)
    }
}

struct LibraryPoster: View {
    let torrent: NativeTorrent
    let metadata: LibraryMetadata?

    var body: some View {
        let metadataPoster = metadata?.posterURL ?? ""
        let value = metadataPoster.isEmpty ? torrent.poster : metadataPoster
        CachedRemoteImage(
            url: value.isEmpty ? nil : URL(string: value),
            contentMode: .fill,
            placeholderSystemImage: "film"
        )
        .posterQuickLook(
            url: value.isEmpty ? nil : URL(string: value),
            title: metadata?.displayTitle ?? torrent.displayTitle
        )
    }
}

struct TorrentLibraryRow: View {
    let torrent: NativeTorrent
    let metadata: LibraryMetadata?
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    private var texts: LibraryTexts {
        LibraryTexts(language: language)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    let posterValue = metadata?.posterURL ?? ""
                    CachedRemoteImage(
                        url: posterValue.isEmpty ? nil : URL(string: posterValue),
                        contentMode: .fill,
                        placeholderSystemImage: "film"
                    )
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .posterQuickLook(
                            url: posterValue.isEmpty ? nil : URL(string: posterValue),
                            title: metadata?.displayTitle ?? torrent.displayTitle
                        )
                    if torrent.isActive {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.green.opacity(0.84), in: Circle())
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata?.displayTitle ?? torrent.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Text(texts.status(for: torrent))
                        Text("·")
                        Text(LibraryFormat.fileSize(torrent.torrentSize))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if torrent.downloadSpeed > 0 {
                    Text(LibraryFormat.speed(torrent.downloadSpeed))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

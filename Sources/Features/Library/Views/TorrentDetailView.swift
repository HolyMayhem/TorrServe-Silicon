import AppKit
import SwiftUI

struct TorrentDetailView: View {
    let torrent: NativeTorrent
    @ObservedObject var model: LibraryViewModel
    let metadata: LibraryMetadata?
    let language: AppLanguage
    let translationMode: OverviewTranslationMode

    private var texts: LibraryTexts {
        LibraryTexts(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                poster

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metadata?.displayTitle ?? torrent.displayTitle)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .lineLimit(3)

                            if let originalTitle = metadata?.originalTitle,
                               !originalTitle.isEmpty,
                               originalTitle != metadata?.displayTitle {
                                Text(originalTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let metadata {
                                Text(metadataFacts(metadata).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if !metadata.genres.isEmpty {
                                    Text(metadata.genres.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if !torrent.category.isEmpty {
                                Text(torrent.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 4)

                        Menu {
                            ForEach(ExternalPlayerChoice.allCases) { choice in
                                Button {
                                    model.setPlayer(choice, language: language)
                                } label: {
                                    if model.playerChoice == choice {
                                        Label(
                                            choice.title(language: language),
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(choice.title(language: language))
                                    }
                                }
                            }
                        } label: {
                            Label(
                                model.playerChoice.title(language: language),
                                systemImage: "play.rectangle"
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button {
                            model.requestRemovalOfSelection()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .help(texts.remove)
                    }

                    if model.resolvingMetadataHashes.contains(torrent.hash.lowercased()) {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text(texts.metadataProviderLoading)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    if let summary = metadata?.summary, !summary.isEmpty {
                        LocalizedOverviewText(
                            sourceText: summary,
                            provider: metadata?.metadataProvider,
                            mediaID: metadata?.metadataProviderID,
                            language: language,
                            translationMode: translationMode,
                            lineLimit: 3,
                            expandedMaximumHeight: 180
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            statistics

            if let progress = torrent.progress {
                VStack(spacing: 4) {
                    HStack {
                        Text(texts.downloaded)
                        Spacer()
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .tint(.green)
                }
            }

            Divider()

            HStack {
                Label(texts.files, systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text(texts.playerHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if torrent.allFiles.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(texts.metadataLoading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(torrent.allFiles, id: \.stableID) { file in
                            TorrentFileRow(
                                file: file,
                                texts: texts
                            ) {
                                model.play(file: file, language: language)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let metadataPoster = metadata?.posterURL ?? ""
        let posterValue = metadataPoster.isEmpty ? torrent.poster : metadataPoster

        if let url = URL(string: posterValue), !posterValue.isEmpty {
            CachedRemoteImage(url: url, contentMode: .fill, placeholderSystemImage: "film")
                .frame(width: 72, height: 96)
                .clipShape(shape)
                .posterQuickLook(
                    url: url,
                    title: metadata?.displayTitle ?? torrent.displayTitle
                )
        } else {
            posterPlaceholder
                .frame(width: 72, height: 96)
                .clipShape(shape)
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "film")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
    }

    private var statistics: some View {
        HStack(spacing: 8) {
            statBadge(
                "\(texts.seeds) \(torrent.connectedSeeders)",
                systemImage: "arrow.up.circle.fill"
            )
            statBadge(
                "\(texts.peers) \(max(torrent.activePeers, torrent.totalPeers))",
                systemImage: "person.2.fill"
            )
            statBadge(
                LibraryFormat.speed(torrent.downloadSpeed),
                systemImage: "arrow.down.circle.fill"
            )
            metadataStatusBadge
            Spacer()
            Text(texts.status(for: torrent))
                .font(.caption)
                .foregroundStyle(torrent.isActive ? Color.green : .secondary)
        }
    }

    private func metadataFacts(_ metadata: LibraryMetadata) -> [String] {
        var values: [String] = []
        if let kind = metadata.mediaKind {
            values.append(kind == .movie
                ? (language == .russian ? "Фильм" : "Movie")
                : (language == .russian ? "Сериал" : "TV"))
        }
        if let releaseDate = metadata.releaseDate, !releaseDate.isEmpty {
            values.append(releaseDate)
        }
        if let season = metadata.season {
            if let episode = metadata.episode {
                values.append(String(format: "S%02dE%02d", season, episode))
            } else {
                values.append(String(format: "S%02d", season))
            }
        }
        if let runtime = metadata.runtimeMinutes, runtime > 0 {
            values.append(language == .russian ? "\(runtime) мин" : "\(runtime) min")
        }
        if let rating = metadata.rating, rating > 0 {
            values.append("★ \(String(format: "%.1f", rating))")
        }
        return values
    }

    private func statBadge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
    }

    @ViewBuilder
    private var metadataStatusBadge: some View {
        let hash = torrent.hash.lowercased()

        if model.resolvingMetadataHashes.contains(hash) {
            Label(
                "\(texts.metadataIndicator): \(texts.metadataIndicatorLoading)",
                systemImage: "hourglass"
            )
            .foregroundStyle(.orange)
            .help(texts.metadataIndicatorLoadingHint)
            .metadataBadgeStyle()
        } else if let source = metadataSourceName {
            Label(
                "\(texts.metadataIndicator): \(source)",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
            .help(texts.metadataIndicatorLoadedHint(source))
            .metadataBadgeStyle()
        } else {
            Label(
                "\(texts.metadataIndicator): \(texts.metadataIndicatorMissing)",
                systemImage: "questionmark.circle"
            )
            .foregroundStyle(.secondary)
            .help(texts.metadataIndicatorMissingHint)
            .metadataBadgeStyle()
        }
    }

    private var metadataSourceName: String? {
        if let provider = metadata?.metadataProvider {
            return provider.displayName
        }
        guard let source = metadata?.source.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }
        return source
    }
}

extension View {
    func metadataBadgeStyle() -> some View {
        font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
    }
}

struct TorrentFileRow: View {
    let file: NativeTorrentFile
    let texts: LibraryTexts
    let play: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isPlayable ? "play.rectangle" : "doc")
                .foregroundStyle(file.isPlayable ? Color.accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(LibraryFormat.fileSize(file.length))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if file.isPlayable {
                Button(action: play) {
                    Label(texts.watch, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
    }
}

import AppKit
import SwiftUI

struct SearchResultRow: View {
    let result: JackettSearchResult
    let isSelected: Bool
    let isAdded: Bool
    let texts: SearchTexts
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                poster

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Label("\(result.seeders)", systemImage: "arrow.up")
                            .foregroundStyle(result.seeders > 0 ? Color.green : .secondary)
                        Label("\(result.peers)", systemImage: "person.2")
                            .foregroundStyle(result.peers > 0 ? Color.blue : .secondary)
                        Text(SearchFormat.fileSize(result.size))
                        if !result.tracker.isEmpty {
                            Text(result.tracker)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 3)
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
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

    @ViewBuilder
    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let url = result.posterURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                posterPlaceholder
            }
            .frame(width: 38, height: 50)
            .clipShape(shape)
        } else {
            posterPlaceholder
                .frame(width: 38, height: 50)
                .clipShape(shape)
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "film")
                .foregroundStyle(.secondary)
        }
    }
}

struct SearchResultDetail: View {
    let result: JackettSearchResult
    @ObservedObject var model: SearchViewModel
    let texts: SearchTexts
    let language: AppLanguage
    let serverIsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                poster

                VStack(alignment: .leading, spacing: 7) {
                    Text(result.title)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if !result.year.isEmpty {
                            badge(result.year, image: "calendar")
                        }
                        badge(
                            SearchFormat.fileSize(result.size),
                            image: "internaldrive"
                        )
                    }

                    if !result.tracker.isEmpty {
                        Label(result.tracker, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                statistic(
                    title: texts.seeds,
                    value: "\(result.seeders)",
                    image: "arrow.up.circle.fill",
                    color: .green
                )
                statistic(
                    title: texts.peers,
                    value: "\(result.peers)",
                    image: "person.2.fill",
                    color: .blue
                )
                Spacer()
            }

            Divider()

            Text(texts.description)
                .font(.headline)

            if result.summary.isEmpty {
                Text(texts.noDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(result.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            if !serverIsRunning {
                Label(texts.startServerFirst, systemImage: "bolt.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if result.detailsURL != nil {
                    Button(texts.openSource) {
                        model.openDetails(for: result)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    model.add(
                        result,
                        language: language,
                        serverIsRunning: serverIsRunning
                    )
                } label: {
                    if model.addingResultID == result.id {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(texts.adding)
                        }
                    } else if model.addedResultIDs.contains(result.id) {
                        Label(texts.added, systemImage: "checkmark")
                    } else {
                        Label(texts.addToLibrary, systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    model.addedResultIDs.contains(result.id)
                        ? Color.green
                        : Color.accentColor
                )
                .disabled(
                    model.addingResultID != nil
                        || model.addedResultIDs.contains(result.id)
                        || !serverIsRunning
                )
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if let url = result.posterURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                posterPlaceholder
            }
            .frame(width: 112, height: 154)
            .clipShape(shape)
        } else {
            posterPlaceholder
                .frame(width: 112, height: 154)
                .clipShape(shape)
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.secondary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private func badge(_ title: String, image: String) -> some View {
        Label(title, systemImage: image)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
    }

    private func statistic(
        title: String,
        value: String,
        image: String,
        color: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: image)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

import SwiftUI

struct CatalogDetailsView: View {
    let item: CatalogItem
    let repository: CatalogRepository
    let connection: CatalogConnection
    let text: CatalogText
    let findTorrents: (CatalogTorrentContext) -> Void
    @State private var details: CatalogDetails?
    @State private var failed = false
    @State private var retry = 0

    private var displayItem: CatalogItem { details?.item ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if details == nil {
                    detailsStatus
                }

                let overview = displayItem.overview.isEmpty ? item.overview : displayItem.overview
                if !overview.isEmpty {
                    Text(overview).textSelection(.enabled)
                }

                if let details {
                    if !details.cast.isEmpty { cast(details.cast) }
                    if !details.seasons.isEmpty { seasons(details.seasons) }
                    if !details.similar.isEmpty { similar(details.similar) }
                }
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .task(id: DetailsRequest(language: text.apiLanguage, timeout: connection.timeout, retry: retry)) {
            failed = false
            do {
                let result = try await repository.details(item.id, language: text.apiLanguage, timeout: connection.timeout)
                if !Task.isCancelled { details = result }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 18) {
            CatalogPoster(url: displayItem.poster ?? item.poster)
                .frame(width: 132, height: 198)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(displayItem.title).font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                if !displayItem.originalTitle.isEmpty, displayItem.originalTitle != displayItem.title {
                    Text(displayItem.originalTitle).font(.title3).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(facts.joined(separator: "  •  ")).foregroundStyle(.secondary)
                if let genres = details?.genres, !genres.isEmpty {
                    Text(genres.map(\.name).joined(separator: " · ")).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button {
                        findTorrents(CatalogTorrentContext(item: item, details: details))
                    } label: {
                        Label(text("Find Torrents", "Найти раздачи"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    if let url = details?.trailer {
                        Link(destination: url) {
                            Label(text("Trailer", "Трейлер"), systemImage: "play.rectangle")
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            if let backdrop = displayItem.backdrop ?? item.backdrop {
                CatalogPoster(url: backdrop)
                    .overlay {
                        LinearGradient(
                            colors: [SettingsVisualStyle.windowBackground.opacity(0.38), SettingsVisualStyle.windowBackground],
                            startPoint: .topTrailing, endPoint: .bottomLeading
                        )
                    }
                    .opacity(0.45)
            } else {
                Color.primary.opacity(0.03)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var facts: [String] {
        var values = [displayItem.id.kind == .movie ? text("Movie", "Фильм") : text("TV Show", "Сериал")]
        if let year = displayItem.year ?? item.year { values.append(String(year)) }
        if let runtime = details?.runtime, runtime > 0 {
            values.append(text("\(runtime) min", "\(runtime) мин"))
        }
        let rating = displayItem.rating > 0 ? displayItem.rating : item.rating
        if rating > 0 {
            values.append("★ " + rating.formatted(.number.precision(.fractionLength(1))))
        }
        return values
    }

    @ViewBuilder
    private var detailsStatus: some View {
        if failed {
            HStack {
                Label(text("More details are unavailable", "Дополнительные сведения недоступны"), systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                Button(text("Retry", "Повторить")) { retry += 1 }
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 3).frame(width: 180, height: 12)
                RoundedRectangle(cornerRadius: 3).frame(width: 110, height: 10)
            }
            .foregroundStyle(Color.primary.opacity(0.08))
            .accessibilityLabel(text("Loading details", "Загрузка сведений"))
        }
    }

    private func cast(_ cast: [CatalogCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Cast", "Актёрский состав")).font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                        VStack(alignment: .leading, spacing: 4) {
                            CatalogPoster(url: member.portrait).frame(width: 80, height: 104)
                                .clipShape(.rect(cornerRadius: 8))
                            Text(member.name).font(.callout.weight(.medium)).lineLimit(2)
                            if let character = member.character, !character.isEmpty {
                                Text(character).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .frame(width: 94, alignment: .leading)
                    }
                }
            }
        }
    }

    private func seasons(_ seasons: [CatalogSeason]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Seasons", "Сезоны")).font(.title3.weight(.semibold))
            ForEach(seasons) { season in
                HStack {
                    Text(season.name)
                    Spacer()
                    if let count = season.episodeCount {
                        Text(text("Episodes: \(count)", "Серий: \(count)")).foregroundStyle(.secondary)
                    }
                    if let date = season.airDate {
                        Text(String(date.prefix(4))).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func similar(_ items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("Similar Titles", "Похожие произведения")).font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { CatalogCard(item: item).frame(width: 126) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct DetailsRequest: Hashable {
        let language: String
        let timeout: TimeInterval
        let retry: Int
    }
}

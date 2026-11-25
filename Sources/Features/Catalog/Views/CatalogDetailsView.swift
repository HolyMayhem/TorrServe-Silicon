import SwiftUI

struct CatalogDetailsView: View {
    let item: CatalogItem
    let repository: CatalogRepository
    let connection: CatalogConnection
    let text: CatalogText
    let openItem: (CatalogItem) -> Void
    let goBack: () -> Void
    let findTorrents: (CatalogTorrentContext) -> Void
    @Environment(\.settingsSidebarIsVisible) private var isSidebarVisible
    @State private var details: CatalogDetails?
    @State private var failed = false
    @State private var retry = 0

    private var displayItem: CatalogItem { details?.item ?? item }
    private var overview: String { displayItem.overview.isEmpty ? item.overview : displayItem.overview }

    var body: some View {
        Group {
            if item.id.kind == .movie { moviePage } else { seriesPage }
        }
        .task(id: DetailsRequest(language: text.apiLanguage, connection: connection.tmdb, retry: retry, identity: item.id)) {
            failed = false
            details = nil
            do {
                let result = try await repository.details(item.id, language: text.apiLanguage, connection: connection.tmdb)
                if !Task.isCancelled { details = result }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private var moviePage: some View {
        GeometryReader { geometry in
            CatalogScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    movieHero(height: min(400, max(340, geometry.size.width * 0.44)))

                    VStack(alignment: .leading, spacing: 28) {
                        if !overview.isEmpty { movieOverview }
                        if details == nil { detailsStatus }
                        if let details {
                            if !details.cast.isEmpty { movieCast(details.cast) }
                            if !details.seasons.isEmpty { seasons(details.seasons) }
                            if !details.similar.isEmpty { similar(details.similar) }
                        }
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .defaultScrollAnchor(.top, for: .sizeChanges)
        }
        .background {
            AppWindowSurface(material: .sidebar)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .controlSize(.large)
            .buttonBorderShape(.circle)
            .liquidGlassControl()
            .accessibilityLabel(text("Back", "Назад"))
            .help(text("Back", "Назад"))
            .accessibilityIdentifier("catalog-movie-back")
            .padding(.leading, isSidebarVisible ? 28 : SettingsScreenLayout.collapsedHeaderLeadingPadding)
            .padding(.top, 8)
        }
    }

    private func movieHero(height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            CatalogPoster(url: displayItem.poster ?? item.poster)
                .frame(width: 140, height: 210)
                .clipShape(.rect(cornerRadius: 9))
                .shadow(color: .black.opacity(0.32), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 7) {
                Text(displayItem.title)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(MoviePalette.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                if !displayItem.originalTitle.isEmpty, displayItem.originalTitle != displayItem.title {
                    Text(displayItem.originalTitle)
                        .font(.system(size: 16))
                        .foregroundStyle(MoviePalette.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Text(facts.joined(separator: "  •  "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MoviePalette.foreground.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let genres = details?.genres, !genres.isEmpty {
                    Text(genres.map(\.name).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(MoviePalette.secondary)
                        .lineLimit(2)
                }

                movieActions.padding(.top, 9)
            }
            .frame(maxWidth: 680, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 76)
        .padding(.bottom, 25)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            Group {
                if let backdrop = displayItem.backdrop ?? item.backdrop {
                    CatalogPoster(url: backdrop)
                        .overlay {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.88), location: 0),
                                    .init(color: .black.opacity(0.68), location: 0.30),
                                    .init(color: .black.opacity(0.36), location: 0.62),
                                    .init(color: .black.opacity(0.05), location: 1)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        }
                } else {
                    Color.black.opacity(0.58)
                }
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.78),
                        .init(color: .black.opacity(0.78), location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    private var movieActions: some View {
        HStack(spacing: 11) {
            Button {
                findTorrents(CatalogTorrentContext(item: item, details: details))
            } label: {
                Label(text("Find Torrents", "Найти раздачи"), systemImage: "magnifyingglass")
            }
            .buttonStyle(MovieActionStyle(minimumWidth: 158))
            .accessibilityIdentifier("catalog-find-torrents")

            if let url = details?.trailer {
                Link(destination: url) {
                    Label(text("Trailer", "Трейлер"), systemImage: "play.fill")
                }
                .buttonStyle(MovieActionStyle(minimumWidth: 112))
                .accessibilityIdentifier("catalog-movie-trailer")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var movieOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            movieHeading(text("Overview", "Описание"))
            Text(overview)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 740, alignment: .leading)
    }

    private func movieCast(_ cast: [CatalogCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            movieHeading(text("Cast", "Актёрский состав"))
            CatalogScrollView(axis: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 8) {
                            CatalogPoster(url: member.portrait)
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                            VStack(spacing: 3) {
                                Text(member.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .help(member.name)
                                if let role = member.character, !role.isEmpty {
                                    Text(role)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .help(role)
                                }
                            }
                        }
                        .multilineTextAlignment(.center)
                        .frame(width: 100)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func movieHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private var seriesPage: some View {
        CatalogScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if details == nil {
                    detailsStatus
                }

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
                    .accessibilityIdentifier("catalog-find-torrents")

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
                            colors: [Color(nsColor: .windowBackgroundColor).opacity(0.38), Color(nsColor: .windowBackgroundColor)],
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
            CatalogScrollView(axis: .horizontal) {
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
            CatalogScrollView(axis: .horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        Button { openItem(item) } label: { CatalogCard(item: item).frame(width: 126) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct DetailsRequest: Hashable {
        let language: String
        let connection: CatalogTMDBConnection
        let retry: Int
        let identity: CatalogIdentity
    }
}

private enum MoviePalette {
    static let foreground = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let secondary = Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)
    static let buttonText = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
}

private struct MovieActionStyle: ButtonStyle {
    let minimumWidth: CGFloat
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MoviePalette.buttonText)
            .padding(.horizontal, 17)
            .frame(minWidth: minimumWidth)
            .frame(height: 42)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.76 : (isHovered ? 0.9 : 1)),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { isHovered = $0 }
    }
}

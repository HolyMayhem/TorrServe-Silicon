import SwiftUI

struct CatalogFiltersView: View {
    @Binding var filter: CatalogFilter
    var fixedKind: MediaKind?
    let repository: CatalogRepository
    let connection: CatalogConnection
    let text: CatalogText
    @State private var loadedGenres: [CatalogGenre] = []

    private var kind: MediaKind? { fixedKind ?? filter.kind }
    private var genres: [CatalogGenre] {
        loadedGenres.isEmpty ? CatalogGenre.defaults(for: kind, russian: text.language == .russian) : loadedGenres
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { controls }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { controls }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: GenreRequest(kind: kind, locale: text.apiLanguage, connection: connection)) {
            loadedGenres = []
            guard connection.source != .cub, let kind else { return }
            let results = try? await repository.genres(kind: kind, language: text.apiLanguage, connection: connection.tmdb)
            if !Task.isCancelled { loadedGenres = results ?? [] }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if fixedKind == nil {
            Picker(text("Type", "Тип"), selection: $filter.kind) {
                Text(text("All", "Все")).tag(nil as MediaKind?)
                Text(text("Movies", "Фильмы")).tag(MediaKind.movie as MediaKind?)
                Text(text("TV Shows", "Сериалы")).tag(MediaKind.tv as MediaKind?)
            }
            .onChange(of: filter.kind) { _, kind in
                let available = CatalogGenre.defaults(for: kind, russian: false)
                if let id = filter.genreID, !available.contains(where: { $0.id == id }) {
                    filter.genreID = nil
                }
            }
        }

        Picker(text("Genre", "Жанр"), selection: $filter.genreID) {
            Text(text("Any", "Любой")).tag(nil as Int?)
            ForEach(genres) { genre in
                Text(genre.name).tag(genre.id as Int?)
            }
        }

        Picker(text("Year", "Год"), selection: $filter.year) {
            Text(text("Any", "Любой")).tag(nil as Int?)
            ForEach(Array((1874...(Calendar(identifier: .gregorian).component(.year, from: .now) + 3)).reversed()), id: \.self) { year in
                Text(String(year)).tag(year as Int?)
            }
        }

        Picker(text("Rating", "Рейтинг"), selection: $filter.minimumRating) {
            Text(text("Any", "Любой")).tag(nil as Int?)
            ForEach(1...10, id: \.self) { rating in
                Text("\(rating)+").tag(rating as Int?)
            }
        }
    }

    private struct GenreRequest: Hashable {
        let kind: MediaKind?
        let locale: String
        let connection: CatalogConnection
    }
}

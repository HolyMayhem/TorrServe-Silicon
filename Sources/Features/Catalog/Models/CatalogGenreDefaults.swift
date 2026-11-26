import Foundation

extension CatalogGenre {
    static func defaults(for kind: MediaKind?, russian: Bool) -> [Self] {
        let shared: [(Int, String, String)] = [
            (16, "Animation", "Мультфильм"), (35, "Comedy", "Комедия"),
            (80, "Crime", "Криминал"), (99, "Documentary", "Документальный"),
            (18, "Drama", "Драма"), (10751, "Family", "Семейный"),
            (9648, "Mystery", "Детектив"), (37, "Western", "Вестерн")
        ]
        let movies: [(Int, String, String)] = [
            (28, "Action", "Боевик"), (12, "Adventure", "Приключения"),
            (14, "Fantasy", "Фэнтези"), (36, "History", "История"),
            (27, "Horror", "Ужасы"), (10402, "Music", "Музыка"),
            (10749, "Romance", "Мелодрама"), (878, "Science Fiction", "Фантастика"),
            (10770, "TV Movie", "Телефильм"), (53, "Thriller", "Триллер"),
            (10752, "War", "Военный")
        ]
        let series: [(Int, String, String)] = [
            (10759, "Action & Adventure", "Боевик и приключения"),
            (10762, "Kids", "Детский"), (10763, "News", "Новости"),
            (10764, "Reality", "Реалити-шоу"), (10765, "Sci-Fi & Fantasy", "Фантастика и фэнтези"),
            (10766, "Soap", "Мыльная опера"), (10767, "Talk", "Ток-шоу"),
            (10768, "War & Politics", "Война и политика")
        ]
        let all = shared + (kind == .tv ? [] : movies) + (kind == .movie ? [] : series)
        return all.map { Self(id: $0.0, name: russian ? $0.2 : $0.1) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

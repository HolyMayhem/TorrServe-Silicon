import Foundation

struct CatalogText {
    let language: AppLanguage

    func callAsFunction(_ english: String, _ russian: String) -> String {
        language == .russian ? russian : english
    }

    var apiLanguage: String { self("en-US", "ru-RU") }

    func title(_ collection: CatalogCollection) -> String {
        switch collection {
        case .trending: self("Trending Now", "Сейчас популярно")
        case .newMovies: self("New Movies", "Новинки кино")
        case .popularMovies: self("Popular Movies", "Популярные фильмы")
        case .popularTV: self("Popular TV Shows", "Популярные сериалы")
        case .upcoming: self("Coming Soon", "Скоро выйдут")
        case .topRated: self("Top Rated", "Лучшие по рейтингу")
        }
    }
}

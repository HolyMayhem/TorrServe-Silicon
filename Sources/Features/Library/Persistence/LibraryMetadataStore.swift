import Foundation

struct LibraryMetadata: Codable, Equatable {
    let title: String
    let posterURL: String
    let summary: String
    let source: String
    let sourceURL: String?
    let tmdbID: Int?
    let metadataProvider: MetadataProvider?
    let metadataProviderID: String?
    let mediaKind: MediaKind?
    let backdropURL: String
    let genres: [String]
    let runtimeMinutes: Int?
    let releaseDate: String?
    let rating: Double?
    let originalTitle: String
    let localizedTitle: String
    let season: Int?
    let episode: Int?
    let metadataLanguage: String?

    init(
        title: String,
        posterURL: String,
        summary: String,
        source: String,
        sourceURL: String? = nil,
        tmdbID: Int? = nil,
        metadataProvider: MetadataProvider? = nil,
        metadataProviderID: String? = nil,
        mediaKind: MediaKind? = nil,
        backdropURL: String = "",
        genres: [String] = [],
        runtimeMinutes: Int? = nil,
        releaseDate: String? = nil,
        rating: Double? = nil,
        originalTitle: String = "",
        localizedTitle: String = "",
        season: Int? = nil,
        episode: Int? = nil,
        metadataLanguage: String? = nil
    ) {
        self.title = title
        self.posterURL = posterURL
        self.summary = summary
        self.source = source
        self.sourceURL = sourceURL
        self.tmdbID = tmdbID
        self.metadataProvider = metadataProvider
        self.metadataProviderID = metadataProviderID
        self.mediaKind = mediaKind
        self.backdropURL = backdropURL
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.releaseDate = releaseDate
        self.rating = rating
        self.originalTitle = originalTitle
        self.localizedTitle = localizedTitle
        self.season = season
        self.episode = episode
        self.metadataLanguage = metadataLanguage
    }

    var displayTitle: String {
        localizedTitle.isEmpty ? title : localizedTitle
    }

    func merging(
        resolved: ResolvedMediaMetadata,
        language: String
    ) -> LibraryMetadata {
        let metadata = resolved.metadata
        let replacesMetadataSource = source.isEmpty || source == "TMDB" || source == "OMDb"
        return LibraryMetadata(
            title: metadata.localizedTitle.isEmpty ? title : metadata.localizedTitle,
            posterURL: metadata.posterURL?.absoluteString ?? posterURL,
            summary: metadata.overview.isEmpty ? summary : metadata.overview,
            source: replacesMetadataSource ? metadata.provider.displayName : source,
            sourceURL: replacesMetadataSource
                ? metadata.provider.sourceURL(id: metadata.id, kind: metadata.kind)?.absoluteString
                : sourceURL,
            tmdbID: metadata.provider == .tmdb ? Int(metadata.id) : nil,
            metadataProvider: metadata.provider,
            metadataProviderID: metadata.id,
            mediaKind: metadata.kind,
            backdropURL: metadata.backdropURL?.absoluteString ?? "",
            genres: metadata.genres,
            runtimeMinutes: metadata.runtimeMinutes,
            releaseDate: metadata.releaseDate,
            rating: metadata.rating,
            originalTitle: metadata.originalTitle,
            localizedTitle: metadata.localizedTitle,
            season: resolved.parsedName.season,
            episode: resolved.parsedName.episode,
            metadataLanguage: language
        )
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case posterURL
        case summary
        case source
        case sourceURL
        case tmdbID
        case metadataProvider
        case metadataProviderID
        case mediaKind
        case backdropURL
        case genres
        case runtimeMinutes
        case releaseDate
        case rating
        case originalTitle
        case localizedTitle
        case season
        case episode
        case metadataLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        posterURL = try container.decodeIfPresent(String.self, forKey: .posterURL) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        tmdbID = try container.decodeIfPresent(Int.self, forKey: .tmdbID)
        metadataProvider = try container.decodeIfPresent(
            MetadataProvider.self,
            forKey: .metadataProvider
        ) ?? (tmdbID == nil ? nil : .tmdb)
        metadataProviderID = try container.decodeIfPresent(
            String.self,
            forKey: .metadataProviderID
        ) ?? tmdbID.map(String.init)
        mediaKind = try container.decodeIfPresent(MediaKind.self, forKey: .mediaKind)
        backdropURL = try container.decodeIfPresent(String.self, forKey: .backdropURL) ?? ""
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle) ?? ""
        localizedTitle = try container.decodeIfPresent(String.self, forKey: .localizedTitle) ?? ""
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        episode = try container.decodeIfPresent(Int.self, forKey: .episode)
        metadataLanguage = try container.decodeIfPresent(String.self, forKey: .metadataLanguage)
    }
}

final class LibraryMetadataStore {
    static let shared = LibraryMetadataStore()

    private let defaultsKey = "LibraryMetadataByTorrentHash"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func metadata(for hash: String) -> LibraryMetadata? {
        allMetadata()[hash.lowercased()]
    }

    func save(_ metadata: LibraryMetadata, for hash: String) {
        guard !hash.isEmpty else { return }
        var values = allMetadata()
        values[hash.lowercased()] = metadata
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    func allMetadata() -> [String: LibraryMetadata] {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let values = try? JSONDecoder().decode(
                [String: LibraryMetadata].self,
                from: data
            )
        else {
            return [:]
        }
        return values
    }
}

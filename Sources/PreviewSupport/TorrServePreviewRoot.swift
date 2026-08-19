#if DEBUG
import SwiftUI

@MainActor
struct TorrServePreviewRoot: View {
    @StateObject private var mainModel: MainWindowModel
    @StateObject private var libraryModel: LibraryViewModel
    @StateObject private var searchModel: SearchViewModel

    init(section: AppSection = .library) {
        let torrents = Self.makeTorrents()

        let mainModel = MainWindowModel()
        mainModel.language = .english
        mainModel.selectedSection = section
        mainModel.path = "/Applications/TorrServer.app/Contents/Resources/TorrServer-darwin-arm64"
        mainModel.statusText = "Running · PID 42042"
        mainModel.statusTooltip = "Preview data"
        mainModel.statusKind = .running
        mainModel.currentSpeedText = "8.4 MB/s"
        mainModel.canStart = false
        mainModel.canStop = true
        mainModel.canOpenWeb = true
        mainModel.canEditPath = false
        mainModel.launchAtLogin = true
        mainModel.autoStartServer = true
        mainModel.showSpeed = true
        mainModel.notificationsEnabled = true
        mainModel.metadataSource = .combined
        mainModel.storage = TorrServerStorageSnapshot(
            cacheUsed: 38 * 1_048_576,
            cacheCapacity: 64 * 1_048_576,
            diskCacheSize: 2_850_000_000,
            freeDiskSpace: 182_000_000_000,
            diskCacheEnabled: true,
            diskCachePath: "/Users/preview/Library/Caches/TorrServer"
        )

        let previewDefaults = UserDefaults(
            suiteName: "TorrServe.XcodePreview.\(UUID().uuidString)"
        ) ?? .standard
        let metadataStore = LibraryMetadataStore(defaults: previewDefaults)
        let metadataSettings = MetadataSettingsStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("torrserve-preview-\(UUID().uuidString).json"),
            legacyTMDBURL: nil,
            builtInAPIKeys: .empty
        )
        let libraryModel = LibraryViewModel(
            metadataStore: metadataStore,
            metadataSettings: metadataSettings,
            allowsAutomaticPolling: false
        )
        libraryModel.playerChoice = .iina
        libraryModel.configurePreview(
            torrents: torrents,
            metadata: Self.makeMetadata(),
            selectedTorrentID: torrents.first?.id
        )

        let searchModel = SearchViewModel(loadsSavedConfiguration: false)
        searchModel.query = "Dune"
        searchModel.results = Self.makeSearchResults()
        searchModel.selectedResultID = searchModel.results.first?.id
        searchModel.connectionIsHealthy = true

        _mainModel = StateObject(wrappedValue: mainModel)
        _libraryModel = StateObject(wrappedValue: libraryModel)
        _searchModel = StateObject(wrappedValue: searchModel)
    }

    var body: some View {
        ApplicationRootView(
            mainModel: mainModel,
            libraryModel: libraryModel,
            searchModel: searchModel
        )
        .frame(width: 1_280, height: 760)
    }

    private static func makeTorrents() -> [NativeTorrent] {
        let json = #"""
        [
          {
            "title": "Dune: Part Two",
            "category": "movie",
            "timestamp": 1710000003,
            "hash": "preview-dune-part-two",
            "stat": 3,
            "stat_string": "Ready",
            "loaded_size": 12884901888,
            "torrent_size": 12884901888,
            "preloaded_bytes": 67108864,
            "preload_size": 67108864,
            "download_speed": 8808038,
            "upload_speed": 245760,
            "total_peers": 34,
            "active_peers": 12,
            "connected_seeders": 18,
            "file_stats": [
              {"id": 0, "path": "Dune.Part.Two.2024.2160p.mkv", "length": 12884901888}
            ]
          },
          {
            "title": "The Last of Us · S02E03",
            "category": "tv",
            "timestamp": 1710000002,
            "hash": "preview-last-of-us",
            "stat": 3,
            "stat_string": "Ready",
            "loaded_size": 5368709120,
            "torrent_size": 7516192768,
            "download_speed": 0,
            "total_peers": 21,
            "active_peers": 0,
            "connected_seeders": 9,
            "file_stats": [
              {"id": 0, "path": "The.Last.of.Us.S02E03.2160p.mkv", "length": 7516192768}
            ]
          },
          {
            "title": "Seven Years in Tibet",
            "category": "movie",
            "timestamp": 1710000001,
            "hash": "preview-seven-years",
            "stat": 3,
            "stat_string": "Ready",
            "loaded_size": 3221225472,
            "torrent_size": 3221225472,
            "download_speed": 0,
            "total_peers": 8,
            "active_peers": 0,
            "connected_seeders": 4,
            "file_stats": [
              {"id": 0, "path": "Seven.Years.in.Tibet.1997.mkv", "length": 3221225472}
            ]
          }
        ]
        """#
        return (try? JSONDecoder().decode([NativeTorrent].self, from: Data(json.utf8))) ?? []
    }

    private static func makeMetadata() -> [String: LibraryMetadata] {
        [
            "preview-dune-part-two": LibraryMetadata(
                title: "Dune: Part Two",
                posterURL: "",
                summary: "Paul Atreides unites with Chani and the Fremen while seeking revenge against the conspirators who destroyed his family.",
                source: "OMDb",
                metadataProvider: .omdb,
                metadataProviderID: "tt15239678",
                mediaKind: .movie,
                genres: ["Science Fiction", "Adventure"],
                runtimeMinutes: 166,
                releaseDate: "2024-03-01",
                rating: 8.5,
                originalTitle: "Dune: Part Two",
                localizedTitle: "Dune: Part Two",
                metadataLanguage: "en"
            ),
            "preview-last-of-us": LibraryMetadata(
                title: "The Last of Us",
                posterURL: "",
                summary: "Joel and Ellie continue their journey through a changed and dangerous America.",
                source: "TMDb",
                tmdbID: 100088,
                metadataProvider: .tmdb,
                metadataProviderID: "100088",
                mediaKind: .tv,
                genres: ["Drama", "Action"],
                runtimeMinutes: 55,
                releaseDate: "2025-04-13",
                rating: 8.7,
                originalTitle: "The Last of Us",
                localizedTitle: "The Last of Us",
                season: 2,
                episode: 3,
                metadataLanguage: "en"
            )
        ]
    }

    private static func makeSearchResults() -> [JackettSearchResult] {
        [
            JackettSearchResult(
                id: "preview-search-1",
                title: "Dune: Part Two (2024) 2160p",
                summary: "Ultra HD release with multiple audio tracks.",
                tracker: "Preview Indexer",
                downloadURL: nil,
                magnetURL: URL(string: "magnet:?xt=urn:btih:preview-dune"),
                posterURL: nil,
                detailsURL: nil,
                size: 12_884_901_888,
                seeders: 184,
                peers: 27,
                categories: ["2000"],
                publishedAt: Date(),
                infoHash: "preview-dune",
                year: "2024"
            ),
            JackettSearchResult(
                id: "preview-search-2",
                title: "Dune Part Two 1080p WEB-DL",
                summary: "Full HD release.",
                tracker: "Preview Indexer",
                downloadURL: nil,
                magnetURL: URL(string: "magnet:?xt=urn:btih:preview-dune-1080"),
                posterURL: nil,
                detailsURL: nil,
                size: 5_368_709_120,
                seeders: 96,
                peers: 14,
                categories: ["2000"],
                publishedAt: Date().addingTimeInterval(-86_400),
                infoHash: "preview-dune-1080",
                year: "2024"
            )
        ]
    }
}
#endif

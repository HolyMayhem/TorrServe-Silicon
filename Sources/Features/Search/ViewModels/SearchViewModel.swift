import AppKit
import Foundation

private let jackettServerURLKey = "JackettServerURL"
private let jackettAPIKeyKey = "JackettAPIKey"


@MainActor
final class SearchViewModel: ObservableObject {
    @Published var serverURL: String
    @Published var apiKey: String
    @Published var query = ""
    @Published private(set) var mode: TorrentSearchMode = .torrentSearch
    @Published private(set) var enabledProviders = Set(TorrentSearchProvider.allCases)
    @Published private(set) var hasSearched = false
    @Published private(set) var pendingSources: Set<String> = []
    @Published private(set) var sourceErrors: [String: String] = [:]
    @Published private(set) var totalSourceCount = 0
    @Published private(set) var successfulSourceCount = 0
    @Published var results: [JackettSearchResult] = []
    @Published var selectedResultID: String?
    @Published private(set) var savedConfiguration: JackettConfiguration?
    @Published var isSearching = false
    @Published var isTesting = false
    @Published var addingResultID: String?
    @Published var addedResultIDs: Set<String> = []
    @Published var connectionMessage = ""
    @Published var connectionIsHealthy = false
    @Published private(set) var jackettConnectionIsHealthy = false
    @Published var showsSettings = false
    @Published var alert: AppAlert?
    @Published var sortField: SearchSortField = .seeders {
        didSet { defaults.set(sortField.rawValue, forKey: "TorrentSearchSortField") }
    }
    @Published var sortAscending = false {
        didSet { defaults.set(sortAscending, forKey: "TorrentSearchSortAscending") }
    }

    var onTorrentAdded: ((String) -> Void)?

    private let torrentSearch: any TorrentSearchServing
    private let jackett: JackettClient
    private let torrServer: any TorrServerServing
    private let credentialStore: any JackettCredentialStoring
    private let defaults: UserDefaults
    private var searchTask: Task<Void, Never>?
    private var searchRevision = 0
    private var activeSearchQuery: String?

    init(
        jackett: JackettClient = JackettClient(),
        torrentSearch: any TorrentSearchServing = TorrentSearchClient(),
        torrServer: any TorrServerServing = NativeTorrServerAPI(),
        defaults: UserDefaults = .standard,
        credentialStore: any JackettCredentialStoring = JackettCredentialStore()
    ) {
        self.jackett = jackett
        self.torrentSearch = torrentSearch
        self.torrServer = torrServer
        self.defaults = defaults
        self.credentialStore = credentialStore
        serverURL = defaults.string(forKey: jackettServerURLKey)
            ?? "http://127.0.0.1:9117"
        let legacyAPIKey = defaults.string(forKey: jackettAPIKeyKey)
            ?? ""
        if let storedAPIKey = credentialStore.read(), !storedAPIKey.isEmpty {
            apiKey = storedAPIKey
        } else {
            apiKey = legacyAPIKey
            if !legacyAPIKey.isEmpty, credentialStore.save(legacyAPIKey) {
                defaults.removeObject(forKey: jackettAPIKeyKey)
            }
        }
        let storedConfiguration = JackettConfiguration(serverURL: serverURL, apiKey: apiKey)
        savedConfiguration = storedConfiguration.isComplete ? storedConfiguration : nil
        mode = defaults.string(forKey: "TorrentSearchMode").flatMap(TorrentSearchMode.init(rawValue:))
            ?? (storedConfiguration.isComplete ? .jackett : .torrentSearch)
        if let providers = defaults.stringArray(forKey: "TorrentSearchEnabledProviders") {
            enabledProviders = Set(providers.compactMap(TorrentSearchProvider.init(rawValue:)))
        }
        sortField = defaults.string(forKey: "TorrentSearchSortField").flatMap(SearchSortField.init(rawValue:)) ?? .seeders
        sortAscending = defaults.bool(forKey: "TorrentSearchSortAscending")
    }

    var configuration: JackettConfiguration {
        JackettConfiguration(serverURL: serverURL, apiKey: apiKey)
    }

    var jackettIsConfigured: Bool { savedConfiguration?.isComplete == true }

    var isConfigured: Bool {
        (mode.usesTorrentSearch && !enabledProviders.isEmpty) || (mode.usesJackett && jackettIsConfigured)
    }

    var completedSourceCount: Int { totalSourceCount - pendingSources.count }

    func setMode(_ mode: TorrentSearchMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: "TorrentSearchMode")
        invalidateSearch()
    }

    func setProvider(_ provider: TorrentSearchProvider, enabled: Bool) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
        defaults.set(TorrentSearchProvider.allCases.filter(enabledProviders.contains).map(\.rawValue), forKey: "TorrentSearchEnabledProviders")
        invalidateSearch()
    }

    private func invalidateSearch() {
        searchTask?.cancel()
        searchRevision += 1
        searchTask = nil
        isSearching = false
        activeSearchQuery = nil
        results = []
        selectedResultID = nil
        hasSearched = false
        sourceErrors = [:]
        pendingSources = []
        totalSourceCount = 0
        successfulSourceCount = 0
    }

    var selectedResult: JackettSearchResult? {
        guard let selectedResultID else { return nil }
        return results.first { $0.id == selectedResultID }
    }

    var sortedResults: [JackettSearchResult] {
        results.sorted { left, right in
            let leftValue = sortValue(for: left)
            let rightValue = sortValue(for: right)

            if sortField == .size {
                if leftValue <= 0, rightValue > 0 { return false }
                if rightValue <= 0, leftValue > 0 { return true }
            }

            if leftValue != rightValue {
                return sortAscending
                    ? leftValue < rightValue
                    : leftValue > rightValue
            }

            if left.seeders != right.seeders {
                return left.seeders > right.seeders
            }
            return left.title.localizedCaseInsensitiveCompare(right.title)
                == .orderedAscending
        }
    }

    private func saveSettings(_ configuration: JackettConfiguration) {
        let normalizedURL = configuration.normalizedServerURL?.absoluteString
            ?? configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURL = normalizedURL
        apiKey = normalizedAPIKey
        defaults.set(normalizedURL, forKey: jackettServerURLKey)
        if credentialStore.save(normalizedAPIKey) {
            defaults.removeObject(forKey: jackettAPIKeyKey)
        } else {
            defaults.set(normalizedAPIKey, forKey: jackettAPIKeyKey)
        }
        savedConfiguration = JackettConfiguration(serverURL: normalizedURL, apiKey: normalizedAPIKey)
    }

    func testConnection(language: AppLanguage, closeOnSuccess: Bool = false) {
        guard !isTesting else { return }
        let candidate = configuration
        guard candidate.isComplete else {
            connectionIsHealthy = false
            jackettConnectionIsHealthy = false
            connectionMessage = SearchTexts(language: language).enterSettings
            return
        }

        isTesting = true
        connectionMessage = ""
        Task {
            defer { isTesting = false }
            do {
                try await jackett.test(configuration: candidate)
                guard candidate == configuration else { return }
                if candidate != savedConfiguration, mode.usesJackett { invalidateSearch() }
                saveSettings(candidate)
                connectionIsHealthy = true
                jackettConnectionIsHealthy = true
                connectionMessage = SearchTexts(language: language).connectionReady
                if closeOnSuccess { showsSettings = false }
            } catch {
                guard candidate == configuration else { return }
                connectionIsHealthy = false
                jackettConnectionIsHealthy = false
                connectionMessage = error.localizedDescription
            }
        }
    }

    func search(language: AppLanguage) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard isConfigured else { showsSettings = true; return }
        guard !isSearching || activeSearchQuery != value else { return }

        searchTask?.cancel()
        searchRevision += 1
        let revision = searchRevision
        let providers = mode.usesTorrentSearch ? TorrentSearchProvider.allCases.filter(enabledProviders.contains) : []
        let jackettConfiguration = mode.usesJackett ? savedConfiguration : nil
        activeSearchQuery = value
        isSearching = true
        hasSearched = true
        results = []
        selectedResultID = nil
        sourceErrors = [:]
        pendingSources = Set(providers.map(\.title) + (jackettConfiguration == nil ? [] : ["Jackett"]))
        totalSourceCount = pendingSources.count
        successfulSourceCount = 0
        if mode.usesJackett && jackettConfiguration == nil {
            sourceErrors["Jackett"] = SearchTexts(language: language).enterSettings
        }
        connectionMessage = ""

        self.searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.searchRevision == revision {
                    self.isSearching = false
                    self.activeSearchQuery = nil
                    self.searchTask = nil
                    self.pendingSources = []
                }
            }
            await withTaskGroup(of: TorrentSearchSourceOutcome.self) { group in
                for provider in providers {
                    let client = self.torrentSearch
                    group.addTask {
                        do {
                            return TorrentSearchSourceOutcome(name: provider.title, results: try await client.search(query: value, provider: provider), error: nil)
                        } catch {
                            return TorrentSearchSourceOutcome(name: provider.title, results: [], error: error.localizedDescription)
                        }
                    }
                }
                if let configuration = jackettConfiguration {
                    let client = self.jackett
                    group.addTask {
                        do {
                            return TorrentSearchSourceOutcome(name: "Jackett", results: try await client.search(query: value, configuration: configuration), error: nil)
                        } catch {
                            return TorrentSearchSourceOutcome(name: "Jackett", results: [], error: error.localizedDescription)
                        }
                    }
                }
                for await outcome in group {
                    guard !Task.isCancelled, self.searchRevision == revision else { group.cancelAll(); return }
                    self.pendingSources.remove(outcome.name)
                    if let error = outcome.error {
                        self.sourceErrors[outcome.name] = error
                    } else {
                        self.successfulSourceCount += 1
                        self.results = TorrentSearchIdentity.merge(self.results + outcome.results)
                        if self.selectedResultID == nil { self.selectedResultID = self.sortedResults.first?.id }
                    }
                }
            }
            guard !Task.isCancelled, self.searchRevision == revision else { return }
            self.connectionIsHealthy = self.successfulSourceCount > 0
        }
    }

    func select(_ result: JackettSearchResult) {
        selectedResultID = result.id
    }

    func toggleSortDirection() {
        sortAscending.toggle()
    }

    func add(
        _ result: JackettSearchResult,
        language: AppLanguage,
        serverIsRunning: Bool
    ) {
        guard serverIsRunning else {
            alert = AppAlert(
                title: "TorrServer",
                message: SearchTexts(language: language).startServerFirst
            )
            return
        }
        guard addingResultID == nil else { return }

        addingResultID = result.id
        Task {
            defer { addingResultID = nil }
            do {
                let payload = try await jackett.download(result)
                let poster = result.posterURL?.absoluteString ?? ""
                let category = result.torrServerCategory
                let torrent: NativeTorrent

                switch payload {
                case .magnet(let magnet):
                    torrent = try await torrServer.addMagnet(
                        magnet,
                        title: result.title,
                        poster: poster,
                        category: category
                    )

                case .torrent(let data, let filename):
                    let values = try await torrServer.uploadTorrent(
                        data: data,
                        filename: filename,
                        title: result.title,
                        poster: poster,
                        category: category
                    )
                    guard let value = values.first else {
                        throw AppError("TorrServer did not return the added torrent.")
                    }
                    torrent = value
                }

                let hash = torrent.hash.isEmpty ? result.infoHash : torrent.hash
                addedResultIDs.insert(result.id)
                onTorrentAdded?(hash)
            } catch {
                alert = AppAlert(
                    title: SearchTexts(language: language).couldNotAdd,
                    message: error.localizedDescription
                )
            }
        }
    }

    func openJackett() {
        guard let url = configuration.normalizedServerURL else { return }
        NSWorkspace.shared.open(url)
    }

    func installJackett() {
        guard let url = URL(string: "https://github.com/Jackett/Jackett/releases/latest") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openJackettProject() {
        guard let url = URL(string: "https://github.com/Jackett/Jackett") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openDetails(for result: JackettSearchResult) {
        guard let url = result.detailsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func sortValue(for result: JackettSearchResult) -> Int64 {
        switch sortField {
        case .seeders:
            return Int64(result.seeders)
        case .peers:
            return Int64(result.peers)
        case .size:
            return result.size
        }
    }
}

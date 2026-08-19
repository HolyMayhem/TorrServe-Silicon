import AppKit
import Foundation
import UniformTypeIdentifiers



@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var torrents: [NativeTorrent] = []
    @Published var selectedTorrentID: String?
    @Published private(set) var selectedTorrentIDs: Set<String> = []
    @Published var searchText = ""
    @Published var magnetInput = ""
    @Published var isRefreshing = false
    @Published var isAdding = false
    @Published var isRemoving = false
    @Published var isDropTargeted = false
    @Published var showsMagnetSheet = false
    @Published var alert: LibraryAlert?
    @Published var playerChoice: ExternalPlayerChoice
    @Published var customPlayerPath: String
    @Published var displayMode: LibraryDisplayMode
    @Published var showsPlayerSetup: Bool
    @Published var detectedPlayers: [DetectedPlayer] = []
    @Published private(set) var pendingDeletionTorrentIDs: Set<String> = []
    @Published private(set) var metadataByHash: [String: LibraryMetadata] = [:]
    @Published private(set) var resolvingMetadataHashes: Set<String> = []

    var onPlayerChanged: ((ExternalPlayerChoice) -> Void)?

    let api: NativeTorrServerAPI
    private let metadataStore: LibraryMetadataStore
    private let metadataResolver: MetadataResolver
    private let metadataSettings: MetadataSettingsStore
    private var refreshTimer: Timer?
    private var metadataResolutionTasks: [String: Task<Void, Never>] = [:]
    private var metadataRetryAfter: [String: Date] = [:]
    private var metadataLanguage = AppLanguage.systemDefault
    private var metadataConfigurationRevision = 0

    init(
        api: NativeTorrServerAPI = NativeTorrServerAPI(),
        metadataStore: LibraryMetadataStore = .shared,
        metadataResolver: MetadataResolver = MetadataResolver(),
        metadataSettings: MetadataSettingsStore = .shared
    ) {
        self.api = api
        self.metadataStore = metadataStore
        self.metadataResolver = metadataResolver
        self.metadataSettings = metadataSettings
        playerChoice = ExternalPlayerChoice(
            rawValue: UserDefaults.standard.string(forKey: libraryPlayerKey) ?? ""
        ) ?? .quickTime
        customPlayerPath = UserDefaults.standard.string(
            forKey: libraryCustomPlayerPathKey
        ) ?? ""
        displayMode = LibraryDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: libraryDisplayModeKey) ?? ""
        ) ?? .compact
        showsPlayerSetup = !UserDefaults.standard.bool(
            forKey: libraryPlayerSetupCompletedKey
        )
        metadataByHash = metadataStore.allMetadata()
        refreshDetectedPlayers()
    }

    var filteredTorrents: [NativeTorrent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return torrents }
        return torrents.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedTorrent: NativeTorrent? {
        guard let selectedTorrentID else { return nil }
        return torrents.first { $0.id == selectedTorrentID }
    }

    var selectedTorrents: [NativeTorrent] {
        torrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    var pendingDeletionTorrents: [NativeTorrent] {
        torrents.filter { pendingDeletionTorrentIDs.contains($0.id) }
    }

    func startPolling() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(silently: true)
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(silently: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            defer { isRefreshing = false }
            do {
                let values = try await api.listTorrents()
                torrents = values
                metadataByHash = metadataStore.allMetadata()
                resolveMetadataIfNeeded(for: values)

                if let selectedTorrentID,
                   !values.contains(where: { $0.id == selectedTorrentID }) {
                    self.selectedTorrentID = nil
                }
                let availableIDs = Set(values.map(\.id))
                self.selectedTorrentIDs.formIntersection(availableIDs)
                if self.selectedTorrentID == nil {
                    self.selectedTorrentID = self.selectedTorrents.first?.id
                        ?? values.first?.id
                }
                if let selectedTorrentID = self.selectedTorrentID {
                    self.selectedTorrentIDs.insert(selectedTorrentID)
                }
            } catch {
                if !silently {
                    showError(error)
                }
            }
        }
    }

    func select(_ torrent: NativeTorrent, extendingSelection: Bool = false) {
        if extendingSelection {
            if selectedTorrentIDs.remove(torrent.id) != nil {
                if selectedTorrentID == torrent.id {
                    selectedTorrentID = torrents.first {
                        selectedTorrentIDs.contains($0.id)
                    }?.id
                }
            } else {
                selectedTorrentIDs.insert(torrent.id)
                selectedTorrentID = torrent.id
            }
        } else {
            selectedTorrentIDs = [torrent.id]
            selectedTorrentID = torrent.id
        }
    }

    func setDisplayMode(_ mode: LibraryDisplayMode) {
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: libraryDisplayModeKey)
    }

    func refreshDetectedPlayers() {
        detectedPlayers = PlayerDetector.detectFeaturedPlayers()
    }

    func metadata(for torrent: NativeTorrent) -> LibraryMetadata? {
        metadataByHash[torrent.hash.lowercased()]
    }

    func setMetadataLanguage(_ language: AppLanguage) {
        guard metadataLanguage != language else { return }
        metadataLanguage = language
        restartMetadataResolution()
    }

    func metadataConfigurationChanged() {
        restartMetadataResolution()
    }

    private func restartMetadataResolution() {
        metadataConfigurationRevision += 1
        metadataResolutionTasks.values.forEach { $0.cancel() }
        metadataResolutionTasks.removeAll()
        resolvingMetadataHashes.removeAll()
        metadataRetryAfter.removeAll()
        metadataStore.removeAll()
        metadataByHash = [:]

        guard !selectedMetadataProviders.isEmpty else { return }
        for torrent in torrents {
            resolveMetadata(for: torrent, forceRefresh: true)
        }
    }

    func refresh(selectingHash: String) {
        if let torrent = torrents.first(where: { $0.hash == selectingHash }) {
            selectedTorrentID = torrent.id
            selectedTorrentIDs = [torrent.id]
        }
        refresh(silently: true)
    }

    func addMagnet(language: AppLanguage) {
        let value = magnetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("magnet:?") else {
            alert = LibraryAlert(
                title: language == .russian ? "Неверная magnet-ссылка" : "Invalid magnet link",
                message: language == .russian
                    ? "Ссылка должна начинаться с magnet:?"
                    : "The link must start with magnet:?"
            )
            return
        }

        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                let torrent = try await api.addMagnet(value)
                magnetInput = ""
                selectedTorrentID = torrent.id
                selectedTorrentIDs = [torrent.id]
                try await refreshImmediately(selectingHash: torrent.hash)
            } catch {
                showError(error)
            }
        }
    }

    func addTorrentFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isAdding = true

        Task {
            defer { isAdding = false }
            do {
                var addedHash: String?
                for url in urls where url.pathExtension.lowercased() == "torrent" {
                    let added = try await api.uploadTorrent(at: url)
                    if addedHash == nil {
                        addedHash = added.first?.hash
                    }
                }
                try await refreshImmediately(selectingHash: addedHash)
            } catch {
                showError(error)
            }
        }
    }

    func chooseTorrentFiles(language: AppLanguage) {
        let panel = NSOpenPanel()
        panel.title = language == .russian
            ? "Выберите torrent-файлы"
            : "Choose .torrent files"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let torrentType = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [torrentType]
        }

        if panel.runModal() == .OK {
            addTorrentFiles(panel.urls)
        }
    }

    func removeSelected() {
        remove(selectedTorrents)
    }

    func remove(_ torrent: NativeTorrent) {
        remove([torrent])
    }

    func remove(_ torrents: [NativeTorrent]) {
        guard !torrents.isEmpty else { return }
        guard !isRemoving else { return }
        isRemoving = true

        Task {
            defer { isRemoving = false }
            do {
                for torrent in torrents {
                    try await api.removeTorrent(hash: torrent.hash)
                    selectedTorrentIDs.remove(torrent.id)
                }
                if let selectedTorrentID,
                   torrents.contains(where: { $0.id == selectedTorrentID }) {
                    self.selectedTorrentID = nil
                }
                try await refreshImmediately(selectingHash: nil)
            } catch {
                showError(error)
            }
        }
    }

    func requestRemoval(of torrent: NativeTorrent) {
        pendingDeletionTorrentIDs = [torrent.id]
    }

    func requestRemovalOfSelection() {
        guard !selectedTorrentIDs.isEmpty else { return }
        pendingDeletionTorrentIDs = selectedTorrentIDs
    }

    func cancelRemoval() {
        pendingDeletionTorrentIDs = []
    }

    func confirmRemoval() {
        let torrents = pendingDeletionTorrents
        pendingDeletionTorrentIDs = []
        remove(torrents)
    }


    func openSource(for torrent: NativeTorrent) {
        guard
            let value = metadata(for: torrent)?.sourceURL,
            let url = URL(string: value)
        else { return }
        NSWorkspace.shared.open(url)
    }

    func showFiles(for torrent: NativeTorrent) {
        select(torrent)
        setDisplayMode(.compact)
    }

    func refreshMetadata(for torrent: NativeTorrent) {
        metadataByHash = metadataStore.allMetadata()
        Task {
            if let refreshed = try? await api.torrent(hash: torrent.hash),
               let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
                torrents[index] = refreshed
                resolveMetadata(for: refreshed, forceRefresh: true)
            } else {
                resolveMetadata(for: torrent, forceRefresh: true)
            }
        }
    }


    private func refreshImmediately(selectingHash: String?) async throws {
        let values = try await api.listTorrents()
        torrents = values
        resolveMetadataIfNeeded(for: values)

        if let selectingHash,
           let selected = values.first(where: { $0.hash == selectingHash }) {
            selectedTorrentID = selected.id
            selectedTorrentIDs = [selected.id]
        } else if selectedTorrentID == nil {
            selectedTorrentID = values.first?.id
            selectedTorrentIDs = values.first.map { [$0.id] } ?? []
        } else {
            let availableIDs = Set(values.map(\.id))
            selectedTorrentIDs.formIntersection(availableIDs)
            if let selectedTorrentID {
                selectedTorrentIDs.insert(selectedTorrentID)
            }
        }
    }

    private func showError(_ error: Error) {
        alert = LibraryAlert(
            title: "TorrServer",
            message: error.localizedDescription
        )
    }

    private var selectedMetadataProviders: [MetadataProvider] {
        metadataSettings.settings.resolutionOrder.filter(metadataSettings.isConfigured)
    }

    private func metadataLanguageCode(for provider: MetadataProvider) -> String {
        provider == .omdb
            ? "en-US"
            : (metadataLanguage == .russian ? "ru-RU" : "en-US")
    }

    private func resolveMetadataIfNeeded(for values: [NativeTorrent]) {
        let providers = selectedMetadataProviders
        guard !providers.isEmpty else { return }
        for torrent in values {
            let hash = torrent.hash.lowercased()
            guard !hash.isEmpty else { continue }
            if let metadata = metadataByHash[hash],
               let provider = metadata.metadataProvider,
               providers.contains(provider),
               metadata.metadataProviderID != nil,
               metadata.metadataLanguage == metadataLanguageCode(for: provider) {
                continue
            }
            resolveMetadata(for: torrent)
        }
    }

    private func resolveMetadata(
        for torrent: NativeTorrent,
        forceRefresh: Bool = false
    ) {
        let providers = selectedMetadataProviders
        guard !providers.isEmpty else { return }
        let hash = torrent.hash.lowercased()
        guard !hash.isEmpty else { return }
        guard metadataResolutionTasks[hash] == nil else { return }
        if !forceRefresh,
           let retryDate = metadataRetryAfter[hash],
           retryDate > Date() {
            return
        }

        let candidates = metadataCandidates(for: torrent)
        let revision = metadataConfigurationRevision
        resolvingMetadataHashes.insert(hash)
        metadataResolutionTasks[hash] = Task { [weak self] in
            guard let self else { return }
            defer {
                if metadataConfigurationRevision == revision {
                    resolvingMetadataHashes.remove(hash)
                    metadataResolutionTasks[hash] = nil
                }
            }
            var providerWasUnavailable = false

            for provider in providers {
                let language = metadataLanguageCode(for: provider)
                let outcome = await metadataResolver.resolve(
                    candidates: candidates,
                    provider: provider,
                    language: language,
                    forceRefresh: forceRefresh
                )
                guard !Task.isCancelled,
                      metadataConfigurationRevision == revision else { return }

                switch outcome {
                case .resolved(let resolved):
                    let metadataValue = resolved.metadata
                    let existing = metadataStore.metadata(for: hash) ?? LibraryMetadata(
                        title: torrent.displayTitle,
                        posterURL: "",
                        summary: "",
                        source: metadataValue.provider.displayName,
                        sourceURL: metadataValue.provider.sourceURL(
                            id: metadataValue.id,
                            kind: metadataValue.kind
                        )?.absoluteString
                    )
                    let metadata = existing.merging(
                        resolved: resolved,
                        language: language
                    )
                    metadataStore.save(metadata, for: hash)
                    metadataByHash[hash] = metadata
                    metadataRetryAfter[hash] = nil
                    return

                case .notFound:
                    continue

                case .unavailable:
                    providerWasUnavailable = true
                    continue
                }
            }

            if providerWasUnavailable {
                metadataRetryAfter[hash] = Date().addingTimeInterval(60 * 15)
            } else {
                metadataRetryAfter[hash] = Date().addingTimeInterval(60 * 60 * 24)
            }
        }
    }

    private func metadataCandidates(for torrent: NativeTorrent) -> [String] {
        var values: [String] = []
        if let largestPlayableFile = torrent.playableFiles.max(by: { $0.length < $1.length }) {
            values.append(largestPlayableFile.displayName)
        }
        values.append(torrent.displayTitle)
        if let name = torrent.name, !name.isEmpty {
            values.append(name)
        }

        var seen: Set<String> = []
        return values.filter { value in
            let normalized = value.lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }
}

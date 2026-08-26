import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var model: LibraryViewModel
    @FocusState private var magnetFieldIsFocused: Bool
    @State private var compactHeaderOverlayHeight: CGFloat = 82
    @State private var compactFooterOverlayHeight: CGFloat = 40
    @State private var compactScrollMetrics = AppScrollMetrics.zero
    @State private var compactScrollIndicatorIsVisible = false

    private let compactScrollEdgeFadeHeight: CGFloat = 17

    private var texts: LibraryTexts {
        LibraryTexts(language: mainModel.language)
    }

    var body: some View {
        libraryContent
        .alert(
            texts.removeMaterialQuestion(count: model.pendingDeletionTorrents.count),
            isPresented: deletionAlertIsPresented
        ) {
            Button(texts.cancel, role: .cancel) {
                model.cancelRemoval()
            }
            Button(texts.remove, role: .destructive) {
                model.confirmRemoval()
            }
        } message: {
            Text(deletionAlertMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showsMagnetSheet) {
            magnetSheet
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            model.startPolling()
        }
        .onDisappear {
            model.stopPolling()
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $model.isDropTargeted,
            perform: handleDrop
        )
        .background {
            LibraryKeyboardShortcutMonitor(
                onDelete: handleDeleteKey,
                onReturn: handleReturnKey
            )
            .frame(width: 0, height: 0)
        }
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { !model.pendingDeletionTorrents.isEmpty },
            set: { isPresented in
                if !isPresented {
                    model.cancelRemoval()
                }
            }
        )
    }

    private var deletionAlertMessage: String {
        let torrents = model.pendingDeletionTorrents
        let subject = torrents.count > 1
            ? texts.selectedMaterialCount(torrents.count)
            : (torrents.first?.displayTitle ?? "")
        return "\(subject)\n\n\(texts.removeMaterialHint(count: torrents.count))"
    }

    private var libraryContent: some View {
        Group {
            if model.displayMode == .compact {
                HStack(spacing: 12) {
                    torrentListPanel
                        .frame(width: 314)

                    torrentDetailPanel
                        .frame(maxWidth: .infinity)
                }
            } else {
                visualLibrary
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var torrentListPanel: some View {
        ZStack {
            if !mainModel.canStop {
                serverUnavailable
                    .padding(.top, compactHeaderOverlayHeight)
                    .padding(.bottom, compactFooterOverlayHeight)
            } else if model.filteredTorrents.isEmpty {
                emptyLibrary
                    .padding(.top, compactHeaderOverlayHeight)
                    .padding(.bottom, compactFooterOverlayHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.filteredTorrents) { torrent in
                            TorrentLibraryRow(
                                torrent: torrent,
                                metadata: model.metadata(for: torrent),
                                language: mainModel.language,
                                isSelected: model.selectedTorrentIDs.contains(torrent.id)
                            ) {
                                select(torrent)
                            }
                            .contextMenu {
                                TorrentContextMenu(
                                    torrent: torrent,
                                    model: model,
                                    language: mainModel.language
                                )
                            }
                        }
                    }
                    .padding(.top, compactHeaderOverlayHeight)
                    .padding(.bottom, compactFooterOverlayHeight)
                    // Keep row backgrounds inside the panel while the custom
                    // scroll indicator remains aligned with the panel edge.
                    .padding(.trailing, 14)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .background {
                    AppNativeScrollIndicatorHider()
                }
                .onScrollGeometryChange(for: AppScrollMetrics.self) { geometry in
                    AppScrollMetrics(geometry)
                } action: { _, metrics in
                    compactScrollMetrics = metrics
                }
                .onScrollPhaseChange { _, phase in
                    withAnimation(.easeOut(duration: phase.isScrolling ? 0.08 : 0.24)) {
                        compactScrollIndicatorIsVisible = phase.isScrolling
                    }
                }
                .mask {
                    AppScrollContentMask(
                        topInset: compactHeaderOverlayHeight,
                        bottomInset: compactFooterOverlayHeight,
                        fadeLength: compactScrollEdgeFadeHeight
                    )
                }
                .overlay {
                    AppScrollIndicator(
                        metrics: compactScrollMetrics,
                        topInset: compactHeaderOverlayHeight,
                        bottomInset: compactFooterOverlayHeight,
                        isVisible: compactScrollIndicatorIsVisible
                    )
                }
            }

            VStack(spacing: 0) {
                compactLibraryHeader

                Spacer(minLength: 0)

                compactLibraryFooter
            }
        }
        .padding(.leading, 14)
        .padding(.top, 14)
        .appPanel()
        .overlay {
            if model.isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor, style: StrokeStyle(
                        lineWidth: 2,
                        dash: [6, 4]
                    ))
            }
        }
    }

    private var compactLibraryHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Label(texts.library, systemImage: "film.stack")
                        .font(.headline)

                    Spacer()

                    LibraryModePicker(model: model, language: mainModel.language)

                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRefreshing || !mainModel.canStop)
                    .help(texts.refresh)

                    Menu {
                        Button {
                            model.showsMagnetSheet = true
                        } label: {
                            Label(texts.addMagnet, systemImage: "link")
                        }

                        Button {
                            model.chooseTorrentFiles(language: mainModel.language)
                        } label: {
                            Label(texts.addTorrentFile, systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(model.isAdding || !mainModel.canStop)
                }

                TextField(texts.search, text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.bottom, compactScrollEdgeFadeHeight)
            .padding(.trailing, 14)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CompactLibraryHeaderHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(CompactLibraryHeaderHeightKey.self) { height in
            guard height > 0 else { return }
            compactHeaderOverlayHeight = height
        }
    }

    private var compactLibraryFooter: some View {
        VStack(spacing: 0) {
            HStack {
                if model.isAdding {
                    ProgressView()
                        .controlSize(.small)
                    Text(texts.adding)
                } else {
                    Text(texts.itemCount(model.torrents.count))
                }

                Spacer()

                Label(texts.dropHint, systemImage: "arrow.down.doc")
            }
            .font(.caption2)
            .foregroundStyle(model.isDropTargeted ? Color.accentColor : .secondary)
            .padding(.top, compactScrollEdgeFadeHeight)
            .padding(.trailing, 14)
        }
        .padding(.bottom, 14)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CompactLibraryFooterHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(CompactLibraryFooterHeightKey.self) { height in
            guard height > 0 else { return }
            compactFooterOverlayHeight = height
        }
    }

    private var visualLibrary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label(texts.library, systemImage: "film.stack")
                    .font(.headline)

                TextField(texts.search, text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Spacer()

                LibraryModePicker(model: model, language: mainModel.language)

                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing || !mainModel.canStop)

                Menu {
                    Button {
                        model.showsMagnetSheet = true
                    } label: {
                        Label(texts.addMagnet, systemImage: "link")
                    }
                    Button {
                        model.chooseTorrentFiles(language: mainModel.language)
                    } label: {
                        Label(texts.addTorrentFile, systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isAdding || !mainModel.canStop)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .appPanel()

            if !mainModel.canStop {
                serverUnavailable
                    .appPanel()
            } else if model.filteredTorrents.isEmpty {
                emptyLibrary
                    .appPanel()
            } else {
                ScrollView {
                    if model.displayMode == .posters {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)],
                            spacing: 16
                        ) {
                            ForEach(model.filteredTorrents) { torrent in
                                TorrentPosterCard(
                                    torrent: torrent,
                                    metadata: model.metadata(for: torrent),
                                    language: mainModel.language,
                                    isSelected: model.selectedTorrentIDs.contains(torrent.id),
                                    select: { select(torrent) },
                                    play: {
                                        model.playFirstFile(
                                            in: torrent,
                                            language: mainModel.language
                                        )
                                    }
                                )
                                .contextMenu {
                                    TorrentContextMenu(
                                        torrent: torrent,
                                        model: model,
                                        language: mainModel.language
                                    )
                                }
                            }
                        }
                        .padding(14)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(model.filteredTorrents) { torrent in
                                TorrentLargeCard(
                                    torrent: torrent,
                                    metadata: model.metadata(for: torrent),
                                    language: mainModel.language,
                                    translationMode: mainModel.overviewTranslationMode,
                                    isSelected: model.selectedTorrentIDs.contains(torrent.id),
                                    select: { select(torrent) },
                                    play: {
                                        model.playFirstFile(
                                            in: torrent,
                                            language: mainModel.language
                                        )
                                    }
                                )
                                .contextMenu {
                                    TorrentContextMenu(
                                        torrent: torrent,
                                        model: model,
                                        language: mainModel.language
                                    )
                                }
                            }
                        }
                        .padding(14)
                    }
                }
                .appPanel()
            }
        }
    }

    @ViewBuilder
    private var torrentDetailPanel: some View {
        if let torrent = model.selectedTorrent {
            TorrentDetailView(
                torrent: torrent,
                model: model,
                metadata: model.metadata(for: torrent),
                language: mainModel.language,
                translationMode: mainModel.overviewTranslationMode
            )
            .padding(14)
            .appPanel()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text(texts.selectMaterial)
                    .font(.headline)
                Text(texts.selectMaterialHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .appPanel()
        }
    }

    private var magnetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(texts.addMagnet, systemImage: "link.badge.plus")
                .font(.title3.weight(.semibold))

            TextField("magnet:?xt=urn:btih:…", text: $model.magnetInput)
                .textFieldStyle(.roundedBorder)
                .focused($magnetFieldIsFocused)

            HStack {
                Text(texts.magnetHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(texts.cancel) {
                    model.showsMagnetSheet = false
                }

                Button(texts.add) {
                    model.addMagnet(language: mainModel.language)
                    model.showsMagnetSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.magnetInput.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            DispatchQueue.main.async {
                magnetFieldIsFocused = true
            }
        }
    }

    private var serverUnavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.slash.circle")
                .font(.system(size: 30, weight: .light))
            Text(texts.serverUnavailable)
                .font(.headline)
            Text(texts.startServerFirst)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(texts.emptyLibrary, systemImage: "tray")
        } description: {
            Text(texts.emptyLibraryHint)
        } actions: {
            HStack {
                Button {
                    model.chooseTorrentFiles(language: mainModel.language)
                } label: {
                    Label(texts.addTorrentFile, systemImage: "doc.badge.plus")
                }
                .disabled(model.isAdding || !mainModel.canStop)
                .help(texts.addTorrentFile)

                Button {
                    model.showsMagnetSheet = true
                } label: {
                    Label(texts.addMagnet, systemImage: "link.badge.plus")
                }
                .disabled(model.isAdding || !mainModel.canStop)
                .help(texts.addMagnet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard
                    let url,
                    url.pathExtension.lowercased() == "torrent"
                else {
                    return
                }

                DispatchQueue.main.async {
                    model.addTorrentFiles([url])
                }
            }
        }
        return accepted
    }

    private func select(_ torrent: NativeTorrent) {
        model.select(
            torrent,
            extendingSelection: NSEvent.modifierFlags.contains(.command)
        )
    }

    private func handleDeleteKey() -> Bool {
        guard !model.showsMagnetSheet,
              model.pendingDeletionTorrents.isEmpty,
              !model.selectedTorrents.isEmpty else {
            return false
        }
        model.requestRemovalOfSelection()
        return true
    }

    private func handleReturnKey() -> Bool {
        guard !model.showsMagnetSheet,
              model.pendingDeletionTorrents.isEmpty else {
            return false
        }
        return model.playSelectedFirstFile(language: mainModel.language)
    }
}

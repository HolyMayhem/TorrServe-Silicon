import SwiftUI

private struct SearchResultsHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SearchView: View {
    @ObservedObject var mainModel: MainWindowModel
    @ObservedObject var model: SearchViewModel
    @FocusState private var searchFieldIsFocused: Bool
    @State private var showsSourceErrors = false
    @State private var resultsHeaderOverlayHeight: CGFloat = 40
    @State private var resultsScrollMetrics = AppScrollMetrics.zero
    @State private var resultsScrollIndicatorIsVisible = false

    private let resultsScrollEdgeFadeHeight: CGFloat = 17
    private let resultsBottomFadeHeight: CGFloat = 40

    private var texts: SearchTexts {
        SearchTexts(language: mainModel.language)
    }

    var body: some View {
        searchContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: mainModel.searchFocusRevision) { _, _ in searchFieldIsFocused = true }
        .sheet(isPresented: $model.showsSettings) {
            SearchSourcesSettingsView(model: model, language: mainModel.language)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var searchContent: some View {
        VStack(spacing: 12) {
            searchBar
            if model.hasSearched { sourceStatus }

            HStack(spacing: 12) {
                resultsPanel
                    .frame(width: 400)
                resultDetailPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(texts.searchPlaceholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFieldIsFocused)
                    .onExitCommand { searchFieldIsFocused = false }
                    .onSubmit { model.search(language: mainModel.language) }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(mainModel.language == .russian ? "Очистить поиск" : "Clear search")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .appToolbarControlSurface()
            .layoutPriority(1)

            Button { model.search(language: mainModel.language) } label: {
                HStack(spacing: 6) {
                    if model.isSearching {
                        ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                    }
                    Text(texts.find)
                }
                .frame(width: 84)
                .appToolbarControlSurface()
            }
            .buttonStyle(.plain)
            .disabled(!model.isConfigured || model.isSearching || model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Menu {
                ForEach(TorrentSearchMode.allCases) { mode in
                    Button { model.setMode(mode) } label: {
                        if mode == model.mode {
                            Label(mode.title(language: mainModel.language), systemImage: "checkmark")
                        } else {
                            Text(mode.title(language: mainModel.language))
                        }
                    }
                }
            } label: {
                Text(model.mode.title(language: mainModel.language))
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .padding(.horizontal, 10)
            .frame(width: 148)
            .appToolbarControlSurface()
            .fixedSize()
            .help(model.mode.detail(language: mainModel.language))
            .accessibilityLabel(mainModel.language == .russian ? "Источник поиска" : "Search source")

            Button { model.showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: AppToolbarMetrics.controlHeight)
                    .appToolbarControlSurface()
            }
            .buttonStyle(.plain)
            .help(mainModel.language == .russian ? "Настроить источники поиска" : "Configure search sources")
            .accessibilityLabel(mainModel.language == .russian ? "Настройки поиска" : "Search settings")
        }
        .padding(8)
        .appPanel()
    }

    private var resultsPanel: some View {
        ZStack {
            if !model.isConfigured {
                setupContent
                    .padding(.top, resultsHeaderOverlayHeight)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
            } else if model.isSearching && model.results.isEmpty {
                searchLoading
                    .padding(.top, resultsHeaderOverlayHeight)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
            } else if model.results.isEmpty {
                searchEmpty
                    .padding(.top, resultsHeaderOverlayHeight)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.sortedResults) { result in
                            SearchResultRow(
                                result: result,
                                isSelected: model.selectedResultID == result.id,
                                isAdded: model.addedResultIDs.contains(result.id),
                                texts: texts
                            ) {
                                model.select(result)
                            }
                        }
                    }
                    .padding(.top, resultsHeaderOverlayHeight)
                    .padding(.bottom, 14)
                    .padding(.trailing, 14)
                    .padding(.vertical, 2)
                    .background {
                        AppNativeScrollIndicatorHider()
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: AppScrollMetrics.self) { geometry in
                    AppScrollMetrics(geometry)
                } action: { _, metrics in
                    resultsScrollMetrics = metrics
                }
                .onScrollPhaseChange { _, phase in
                    withAnimation(.easeOut(duration: phase.isScrolling ? 0.08 : 0.24)) {
                        resultsScrollIndicatorIsVisible = phase.isScrolling
                    }
                }
                .mask {
                    AppScrollContentMask(
                        topInset: resultsHeaderOverlayHeight,
                        bottomInset: resultsBottomFadeHeight,
                        fadeLength: resultsScrollEdgeFadeHeight
                    )
                }
                .overlay {
                    AppScrollIndicator(
                        metrics: resultsScrollMetrics,
                        topInset: resultsHeaderOverlayHeight,
                        bottomInset: 4,
                        isVisible: resultsScrollIndicatorIsVisible
                    )
                }
            }

            VStack(spacing: 0) {
                resultsHeader
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 14)
        .padding(.top, 14)
        .appPanel()
    }

    private var resultsHeader: some View {
        HStack {
            Label(texts.results, systemImage: "list.bullet.rectangle")
                .font(.headline)
            Spacer()

            sortMenu
            if !model.results.isEmpty {
                Text("\(model.results.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, resultsScrollEdgeFadeHeight)
        .padding(.trailing, 14)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchResultsHeaderHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(SearchResultsHeaderHeightKey.self) { height in
            guard height > 0 else { return }
            resultsHeaderOverlayHeight = height
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SearchSortField.allCases) { field in
                Button {
                    model.sortField = field
                } label: {
                    if model.sortField == field {
                        Label(
                            texts.sortTitle(for: field),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(texts.sortTitle(for: field))
                    }
                }
            }

            Divider()

            ForEach([false, true], id: \.self) { ascending in
                Button { model.sortAscending = ascending } label: {
                    if model.sortAscending == ascending {
                        Label(ascending ? texts.ascending : texts.descending, systemImage: "checkmark")
                    } else {
                        Text(ascending ? texts.ascending : texts.descending)
                    }
                }
            }
        } label: {
            Label(
                texts.sortTitle(for: model.sortField),
                systemImage: model.sortAscending ? "arrow.up" : "arrow.down"
            )
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(texts.sort)
    }

    @ViewBuilder
    private var resultDetailPanel: some View {
        if let result = model.selectedResult {
            SearchResultDetail(
                result: result,
                model: model,
                texts: texts,
                language: mainModel.language,
                serverIsRunning: mainModel.canStop
            )
            .padding(16)
            .appPanel()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text(texts.selectResult)
                    .font(.headline)
                Text(texts.selectResultHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .appPanel()
        }
    }

    private var searchLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(mainModel.language == .russian ? "Поиск по источникам…" : "Searching sources…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceStatus: some View {
        HStack(spacing: 8) {
            if model.isSearching { ProgressView().controlSize(.mini) }
            Text(mainModel.language == .russian
                ? "Ответили источники: \(model.completedSourceCount) из \(model.totalSourceCount)"
                : "Sources responded: \(model.completedSourceCount) of \(model.totalSourceCount)")
                .foregroundStyle(.secondary)
            Spacer()
            if !model.sourceErrors.isEmpty {
                Button {
                    showsSourceErrors.toggle()
                } label: {
                    Label(mainModel.language == .russian ? "Недоступны: \(model.sourceErrors.count)" : "Unavailable: \(model.sourceErrors.count)", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .popover(isPresented: $showsSourceErrors) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.sourceErrors.keys.sorted(), id: \.self) { name in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name).font(.headline)
                                Text(model.sourceErrors[name] ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(16).frame(width: 330)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private var searchEmpty: some View {
        VStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
            Text(model.hasSearched
                ? (model.successfulSourceCount == 0
                    ? (mainModel.language == .russian ? "Источники недоступны" : "Sources Unavailable")
                    : (mainModel.language == .russian ? "Раздачи не найдены" : "No releases found"))
                : texts.startSearching)
                .font(.headline)
            Text(model.hasSearched
                ? (mainModel.language == .russian ? "Измените запрос или выберите другие источники. Сведения о недоступных источниках показаны над списком." : "Try another query or different sources. Unavailable sources are listed above.")
                : model.mode.detail(language: mainModel.language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var setupContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(mainModel.language == .russian ? "Настройте источники" : "Choose Your Sources")
                .font(.headline)
            Text(model.mode == .jackett ? texts.connectJackettHint
                : (mainModel.language == .russian ? "Включите хотя бы один источник TorrentSearch или подключите Jackett." : "Enable a TorrentSearch source or connect Jackett."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(mainModel.language == .russian ? "Настроить поиск…" : "Configure Search…") { model.showsSettings = true }
                .buttonStyle(.borderedProminent)
            if model.mode == .jackett {
                Button(mainModel.language == .russian ? "Использовать TorrentSearch" : "Use TorrentSearch") { model.setMode(.torrentSearch) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

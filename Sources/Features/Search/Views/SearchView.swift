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
    @State private var resultsHeaderOverlayHeight: CGFloat = 40
    @State private var resultsScrollMetrics = LibraryScrollMetrics.zero
    @State private var resultsScrollIndicatorIsVisible = false

    private let resultsScrollEdgeFadeHeight: CGFloat = 17
    private let resultsBottomFadeHeight: CGFloat = 40

    private var texts: SearchTexts {
        SearchTexts(language: mainModel.language)
    }

    var body: some View {
        Group {
            if model.isConfigured {
                searchContent
            } else {
                setupContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showsSettings) {
            settingsSheet
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

            HStack(spacing: 12) {
                resultsPanel
                    .frame(width: 400)
                resultDetailPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(texts.searchPlaceholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        model.search(language: mainModel.language)
                    }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                Color.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            Button {
                model.search(language: mainModel.language)
            } label: {
                HStack(spacing: 7) {
                    if model.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(texts.find)
                }
                .frame(minWidth: 78)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                model.isSearching
                    || model.query.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            )

            Button {
                model.showsSettings = true
            } label: {
                Label("Jackett", systemImage: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(10)
        .searchPanel()
    }

    private var resultsPanel: some View {
        ZStack {
            if model.isSearching && model.results.isEmpty {
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
                    // Match the compact Library list: SwiftUI reserves a hidden
                    // 17 pt trailing gutter even without the native scroller.
                    .padding(.trailing, -3)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .background {
                    LibraryNativeScrollIndicatorHider()
                }
                .onScrollGeometryChange(for: LibraryScrollMetrics.self) { geometry in
                    LibraryScrollMetrics(geometry)
                } action: { _, metrics in
                    resultsScrollMetrics = metrics
                }
                .onScrollPhaseChange { _, phase in
                    withAnimation(.easeOut(duration: phase.isScrolling ? 0.08 : 0.24)) {
                        resultsScrollIndicatorIsVisible = phase.isScrolling
                    }
                }
                .mask {
                    LibraryScrollContentMask(
                        topInset: resultsHeaderOverlayHeight,
                        bottomInset: resultsBottomFadeHeight,
                        fadeLength: resultsScrollEdgeFadeHeight
                    )
                }
                .overlay {
                    LibraryScrollIndicator(
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
        .searchPanel()
    }

    private var resultsHeader: some View {
        HStack {
            Label(texts.results, systemImage: "list.bullet.rectangle")
                .font(.headline)
            Spacer()

            if !model.results.isEmpty {
                sortMenu

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

            Button {
                model.toggleSortDirection()
            } label: {
                Label(
                    model.sortAscending
                        ? texts.ascending
                        : texts.descending,
                    systemImage: model.sortAscending
                        ? "arrow.up"
                        : "arrow.down"
                )
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
            .searchPanel()
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
            .searchPanel()
        }
    }

    private var searchLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(texts.searching)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchEmpty: some View {
        VStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
            Text(texts.startSearching)
                .font(.headline)
            Text(texts.startSearchingHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupContent: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 76, height: 76)
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(texts.connectJackett)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(texts.connectJackettHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            configurationFields
                .frame(width: 540)

            HStack {
                Button(texts.openProject) {
                    model.openJackettProject()
                }
                .buttonStyle(.bordered)

                Button {
                    model.testConnection(
                        language: mainModel.language,
                        closeOnSuccess: false
                    )
                } label: {
                    if model.isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(texts.connect, systemImage: "bolt.horizontal")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isTesting || !model.configuration.isComplete)
            }

            connectionStatus
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .searchPanel()
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(texts.jackettSettings, systemImage: "gearshape.2")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.showsSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(texts.settingsHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            configurationFields
            connectionStatus

            HStack {
                Button(texts.openJackett) {
                    model.openJackett()
                }
                .disabled(model.configuration.normalizedServerURL == nil)

                Button(texts.installJackett) {
                    model.installJackett()
                }

                Spacer()

                Button(texts.saveAndCheck) {
                    model.testConnection(
                        language: mainModel.language,
                        closeOnSuccess: true
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isTesting || !model.configuration.isComplete)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var configurationFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(texts.jackettAddress)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("http://127.0.0.1:9117", text: $model.serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(texts.apiKey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                SecureField(texts.apiKeyPlaceholder, text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if !model.connectionMessage.isEmpty {
            Label(
                model.connectionMessage,
                systemImage: model.connectionIsHealthy
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(
                model.connectionIsHealthy ? Color.green : Color.orange
            )
            .lineLimit(2)
        }
    }
}

import SwiftUI

struct CatalogSettingsView: View {
    let text: CatalogText

    @ObservedObject private var store = CatalogSettingsStore.shared
    @Environment(\.isIndexingSettings) private var isIndexingSettings
    @Environment(\.settingsSearchRequest) private var searchRequest
    @FocusState private var focusedField: Field?
    @State private var draft = Draft()
    @State private var showsAdvanced = false
    @State private var status: String?
    @State private var failed = false

    private let advancedSection = "catalog-advanced"
    private enum Field: Hashable { case cubURL, cubToken, proxy, imageMirror }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sourceSettings

            if isIndexingSettings {
                advancedSettings
            } else {
                DisclosureGroup(isExpanded: $showsAdvanced) {
                    advancedSettings.padding(.top, 14)
                } label: {
                    Text(text("Advanced", "Дополнительно"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 12) {
                if let status {
                    Text(status)
                        .foregroundStyle(failed ? Color.red : Color.secondary)
                        .font(.callout)
                }
                Spacer()
                Button(text("Save", "Сохранить"), action: save)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
        }
        .onAppear {
            if !isIndexingSettings { draft = Draft(connection: store.connection) }
        }
        .onChange(of: draft) { _, _ in status = nil }
        .onChange(of: searchRequest?.revision, initial: true) { _, _ in
            if searchRequest?.entry.revealSection == advancedSection { showsAdvanced = true }
        }
    }

    private var sourceSettings: some View {
        ServerSettingsGroup(title: text("Catalog Source", "Источник каталога"), footer: sourceDescription) {
            let title = text("Source", "Источник")
            HStack(spacing: 16) {
                Text(title)
                Spacer(minLength: 12)
                Picker(title, selection: $draft.source) {
                    Text(text("Auto", "Авто")).tag(CatalogSource.auto)
                    Text("TMDB").tag(CatalogSource.tmdb)
                    Text("CUB").tag(CatalogSource.cub)
                }
                .labelsHidden()
                .fixedSize()
            }
            .frame(minHeight: 46)
            .searchableSetting(title)
        }
    }

    private var sourceDescription: String {
        switch draft.source {
        case .auto:
            text("Tries TMDB first and switches to CUB if the catalog is unavailable.",
                 "Сначала загружает каталог из TMDB. Если TMDB недоступен, переключается на CUB.")
        case .tmdb:
            text("Loads the catalog and title details from TMDB.",
                 "Загружает каталог и сведения о фильмах и сериалах из TMDB.")
        case .cub:
            text("Loads the catalog from CUB. Extended title details come from TMDB.",
                 "Загружает каталог из CUB. Подробные сведения о фильмах и сериалах берутся из TMDB.")
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            ServerSettingsGroup(
                title: text("CUB Server", "Сервер CUB"),
                footer: text("Leave these fields empty to use the public CUB server.",
                             "Оставьте поля пустыми, чтобы использовать публичный сервер CUB.")
            ) {
                inputRow(.cubURL, title: text("CUB server URL", "URL сервера CUB"),
                         placeholder: CatalogConnection.publicCUB.absoluteString, value: $draft.cubURL)
                Divider()
                inputRow(.cubToken, title: text("CUB token", "Токен CUB"),
                         placeholder: text("Optional", "Необязательно"), value: $draft.cubToken)
            }

            ServerSettingsGroup(
                title: text("Custom Connection", "Своё подключение"),
                footer: text("The TMDB proxy receives your API key. Use a server you trust.",
                             "Прокси получает ваш ключ TMDB. Указывайте только доверенный сервер.")
            ) {
                inputRow(.proxy, title: text("TMDB proxy URL", "URL прокси TMDB"),
                         placeholder: "https://", value: proxyAddress)

                if !draft.proxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (isIndexingSettings && store.connection.tmdb.proxy != nil) {
                    Divider()
                    connectionMode
                }

                Divider()
                inputRow(.imageMirror, title: text("Poster mirror URL", "URL зеркала постеров"),
                         placeholder: "https://", value: $draft.imageMirror)
            }
        }
        .environment(\.settingsSearchRevealSection, advancedSection)
    }

    private var proxyAddress: Binding<String> {
        Binding(
            get: { draft.proxy },
            set: { value in
                if draft.proxy.isEmpty && !value.isEmpty && draft.route == .direct { draft.route = .auto }
                draft.proxy = value
            }
        )
    }

    private var connectionMode: some View {
        let title = text("TMDB connection", "Подключение к TMDB")
        return HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            Picker(title, selection: $draft.route) {
                Text(text("Auto", "Авто")).tag(CatalogTMDBRoute.auto)
                Text(text("Direct", "Прямое")).tag(CatalogTMDBRoute.direct)
                if store.connection.tmdb.route == .proxy {
                    Text(text("Proxy only", "Только прокси")).tag(CatalogTMDBRoute.proxy)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .frame(minHeight: 46)
        .searchableSetting(title)
    }

    private func inputRow(_ field: Field, title: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
            Group {
                if field == .cubToken {
                    SecureField(title, text: value, prompt: Text(placeholder))
                } else {
                    TextField(title, text: value, prompt: Text(placeholder))
                }
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($focusedField, equals: field)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .appToolbarControlSurface()
            .overlay {
                if focusedField == field {
                    RoundedRectangle(cornerRadius: AppToolbarMetrics.cornerRadius)
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .onSubmit(save)
        }
        .padding(.vertical, 12)
        .searchableSetting(title)
    }

    private func save() {
        failed = true
        let values = [draft.cubURL, draft.proxy, draft.imageMirror].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard values.allSatisfy({ $0.isEmpty || CatalogConnection.endpoint($0) != nil }) else {
            status = text("Enter HTTPS base URLs without credentials, query or fragment.",
                          "Укажите базовые HTTPS-адреса без учётных данных, параметров и фрагментов.")
            return
        }

        let token = draft.cubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.utf8.count <= 4_096, token.utf8.allSatisfy({ (32...126).contains($0) }) else {
            status = text("Enter a valid CUB token.", "Укажите допустимый токен CUB.")
            return
        }

        let proxy = CatalogConnection.endpoint(values[1])
        let connection = CatalogConnection(
            source: draft.source, cubURL: CatalogConnection.endpoint(values[0]) ?? CatalogConnection.publicCUB,
            cubToken: token,
            tmdb: CatalogTMDBConnection(
                route: proxy == nil ? .direct : draft.route, proxy: proxy, timeout: store.connection.timeout
            ),
            imageMirror: CatalogConnection.endpoint(values[2])
        )
        guard store.save(connection) else {
            status = text("Could not save the token in Keychain.", "Не удалось сохранить токен в Связке ключей.")
            return
        }
        failed = false
        status = text("Saved", "Сохранено")
    }

    private struct Draft: Equatable {
        var source: CatalogSource
        var cubURL: String
        var cubToken: String
        var route: CatalogTMDBRoute
        var proxy: String
        var imageMirror: String

        init(connection: CatalogConnection = CatalogConnection()) {
            source = connection.source
            cubURL = connection.cubURL == CatalogConnection.publicCUB ? "" : connection.cubURL.absoluteString
            cubToken = connection.cubToken
            route = connection.tmdb.route
            proxy = connection.tmdb.proxy?.absoluteString ?? ""
            imageMirror = connection.imageMirror?.absoluteString ?? ""
        }
    }
}

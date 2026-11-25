import SwiftUI

struct CatalogSettingsView: View {
    let text: CatalogText
    @ObservedObject private var store = CatalogSettingsStore.shared
    @State private var source: CatalogSource = .tmdb
    @State private var cubURL = ""
    @State private var cubToken = ""
    @State private var route: CatalogTMDBRoute = .direct
    @State private var proxy = ""
    @State private var mirror = ""
    @State private var timeout = 12.0
    @State private var status: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ServerSettingsGroup(title: text("Catalog Source", "Источник каталога")) {
                let sourceTitle = text("Source", "Источник")
                Picker(sourceTitle, selection: $source) {
                    Text("TMDB").tag(CatalogSource.tmdb)
                    Text("CUB").tag(CatalogSource.cub)
                    Text(text("Auto", "Авто")).tag(CatalogSource.auto)
                }
                .searchableSetting(sourceTitle)
                Divider()
                TextField(text("CUB URL", "URL CUB"), text: $cubURL, prompt: Text(CatalogConnection.publicCUB.absoluteString))
                    .searchableSetting(text("CUB URL", "URL CUB"))
                SecureField(text("CUB token (optional)", "Токен CUB (необязательно)"), text: $cubToken)
                    .searchableSetting(text("CUB token", "Токен CUB"))
            }

            ServerSettingsGroup(
                title: text("Network", "Сеть"),
                footer: text(
                    "The TMDB proxy URL must point to a compatible API base. Proxy requests send your existing TMDB API key to that address.",
                    "URL прокси должен указывать на совместимый API TMDB. В запросах через прокси используется ваш текущий ключ TMDB."
                )
            ) {
                let mode = text("TMDB connection", "Подключение к TMDB")
                Picker(mode, selection: $route) {
                    Text(text("Direct", "Прямое")).tag(CatalogTMDBRoute.direct)
                    Text(text("Try proxy on failure", "Прокси при ошибке")).tag(CatalogTMDBRoute.auto)
                    Text(text("Proxy only", "Только прокси")).tag(CatalogTMDBRoute.proxy)
                }
                .searchableSetting(mode)
                TextField(text("TMDB proxy URL", "URL прокси TMDB"), text: $proxy)
                    .searchableSetting(text("TMDB proxy URL", "URL прокси TMDB"))
                TextField(text("Image mirror URL", "URL зеркала изображений"), text: $mirror)
                    .searchableSetting(text("Image mirror URL", "URL зеркала изображений"))
                Stepper(value: $timeout, in: 5...30, step: 1) {
                    Text(text("Request timeout: \(Int(timeout)) s", "Тайм-аут запроса: \(Int(timeout)) с"))
                }
                .searchableSetting(text("Request timeout", "Тайм-аут запроса"))
            }

            HStack {
                if let status {
                    Text(status).foregroundStyle(failed ? Color.red : Color.secondary)
                }
                Spacer()
                Button(text("Save", "Сохранить"), action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            let connection = store.connection
            source = connection.source
            cubURL = connection.cubURL == CatalogConnection.publicCUB ? "" : connection.cubURL.absoluteString
            cubToken = connection.cubToken
            route = connection.tmdb.route
            proxy = connection.tmdb.proxy?.absoluteString ?? ""
            mirror = connection.imageMirror?.absoluteString ?? ""
            timeout = connection.timeout
        }
    }

    private func save() {
        failed = true
        let values = [cubURL, proxy, mirror].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.allSatisfy({ $0.isEmpty || CatalogConnection.endpoint($0) != nil }) else {
            status = text("Enter HTTPS base URLs without credentials, query or fragment.", "Укажите базовые HTTPS-адреса без учётных данных, параметров и фрагментов.")
            return
        }
        let proxy = CatalogConnection.endpoint(values[1])
        guard route == .direct || proxy != nil else {
            status = text("Enter a TMDB proxy URL.", "Укажите URL прокси TMDB.")
            return
        }
        let token = cubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.utf8.count <= 4_096,
              token.utf8.allSatisfy({ (32...126).contains($0) }) else {
            status = text("Enter a valid CUB token.", "Укажите допустимый токен CUB.")
            return
        }

        let connection = CatalogConnection(
            source: source, cubURL: CatalogConnection.endpoint(values[0]) ?? CatalogConnection.publicCUB,
            cubToken: token, tmdb: CatalogTMDBConnection(route: route, proxy: proxy, timeout: timeout),
            imageMirror: CatalogConnection.endpoint(values[2])
        )
        guard store.save(connection) else {
            status = text("Could not save the token in Keychain.", "Не удалось сохранить токен в Связке ключей.")
            return
        }
        failed = false
        status = text("Saved", "Сохранено")
    }
}

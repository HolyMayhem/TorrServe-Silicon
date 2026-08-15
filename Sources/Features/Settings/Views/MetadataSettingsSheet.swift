import SwiftUI

struct MetadataSettingsSheet: View {
    let language: AppLanguage
    let provider: MetadataProvider
    let save: (String, OverviewTranslationMode) -> Void
    let cancel: () -> Void

    @State private var apiKey: String
    @State private var translationMode: OverviewTranslationMode

    init(
        language: AppLanguage,
        provider: MetadataProvider,
        initialAPIKey: String,
        initialTranslationMode: OverviewTranslationMode,
        save: @escaping (String, OverviewTranslationMode) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.language = language
        self.provider = provider
        self.save = save
        self.cancel = cancel
        _apiKey = State(initialValue: initialAPIKey)
        _translationMode = State(initialValue: initialTranslationMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                language == .russian
                    ? "Метаданные \(provider.displayName)"
                    : "\(provider.displayName) Metadata",
                systemImage: "photo.on.rectangle.angled"
            )
            .font(.title3.weight(.semibold))

            Text(language == .russian
                ? "Укажите API Key для \(provider.displayName). Ключ хранится локально и используется только для запросов метаданных."
                : "Enter the \(provider.displayName) API Key. It is stored locally and used only for metadata requests.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("\(provider.displayName) API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            if provider == .omdb {
                VStack(alignment: .leading, spacing: 7) {
                    Text(language == .russian ? "Перевод описаний" : "Overview translation")
                        .font(.subheadline.weight(.medium))

                    Picker("", selection: $translationMode) {
                        Text(language == .russian ? "Автоматически" : "Automatic")
                            .tag(OverviewTranslationMode.automatic)
                        Text(language == .russian ? "Оригинал" : "Original")
                            .tag(OverviewTranslationMode.original)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(language == .russian
                        ? "В русской версии английские описания OMDb переводятся средствами macOS. Оригинал всегда сохраняется."
                        : "In the Russian interface, English OMDb overviews are translated by macOS. The original is always preserved.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Link(
                    language == .russian ? "Получить API Key" : "Get an API Key",
                    destination: apiKeyURL
                )

                Spacer()

                Button(language == .russian ? "Отмена" : "Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button(language == .russian ? "Сохранить" : "Save") {
                    save(
                        apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        translationMode
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var attribution: String {
        switch provider {
        case .tmdb:
            return language == .russian
                ? "Этот продукт использует TMDB API, но не одобрен и не сертифицирован TMDB."
                : "This product uses the TMDB API but is not endorsed or certified by TMDB."
        case .omdb:
            return language == .russian
                ? "OMDb предоставляет постеры и данные IMDb, но не поддерживает локализацию и фоновые изображения."
                : "OMDb provides posters and IMDb data, but does not provide localization or backdrop images."
        case .kinopoisk:
            return language == .russian
                ? "Данные предоставляются неофициальным API КиноПоиска. Доступность и лимиты зависят от тарифа API."
                : "Data is provided by the unofficial Kinopoisk API. Availability and limits depend on its API plan."
        }
    }

    private var apiKeyURL: URL {
        switch provider {
        case .tmdb:
            return URL(string: "https://www.themoviedb.org/settings/api")!
        case .omdb:
            return URL(string: "https://www.omdbapi.com/apikey.aspx")!
        case .kinopoisk:
            return URL(string: "https://kinopoiskapiunofficial.tech/profile")!
        }
    }
}

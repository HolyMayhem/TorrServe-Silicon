import Foundation
import SwiftUI

struct SearchTexts {
    let language: AppLanguage

    var find: String { language == .russian ? "Найти" : "Search" }
    var searchPlaceholder: String {
        language == .russian
            ? "Название фильма или сериала"
            : "Movie or series title"
    }
    var results: String { language == .russian ? "Результаты" : "Results" }
    var sort: String { language == .russian ? "Сортировка" : "Sort" }
    var ascending: String {
        language == .russian ? "По возрастанию" : "Ascending"
    }
    var descending: String {
        language == .russian ? "По убыванию" : "Descending"
    }
    func sortTitle(for field: SearchSortField) -> String {
        switch field {
        case .seeders:
            return language == .russian ? "Сиды" : "Seeders"
        case .peers:
            return language == .russian ? "Пиры" : "Peers"
        case .size:
            return language == .russian ? "Размер" : "Size"
        }
    }
    var searching: String { language == .russian ? "Поиск в Jackett…" : "Searching Jackett…" }
    var startSearching: String { language == .russian ? "Найдите фильм" : "Find something to watch" }
    var startSearchingHint: String {
        language == .russian
            ? "Jackett выполнит поиск по подключённым торрент-трекерам."
            : "Jackett will search your configured torrent indexers."
    }
    var selectResult: String { language == .russian ? "Выберите раздачу" : "Select a release" }
    var selectResultHint: String {
        language == .russian
            ? "Здесь появятся описание, обложка и кнопка добавления."
            : "Poster, description, and add controls will appear here."
    }
    var connectJackett: String { language == .russian ? "Подключите Jackett" : "Connect Jackett" }
    var connectJackettHint: String {
        language == .russian
            ? "Укажите адрес и API-ключ из панели Jackett. После этого поиск будет работать прямо внутри TorrServer."
            : "Enter the address and API key from Jackett. Search will then work directly inside TorrServer."
    }
    var jackettAddress: String { language == .russian ? "Адрес Jackett" : "Jackett address" }
    var apiKey: String { "API key" }
    var apiKeyPlaceholder: String {
        language == .russian ? "API-ключ из Jackett" : "API key from Jackett"
    }
    var connect: String { language == .russian ? "Подключить" : "Connect" }
    var openProject: String {
        language == .russian ? "Открыть проект Jackett" : "Open Jackett project"
    }
    var connectionReady: String {
        language == .russian ? "Jackett подключён и готов к поиску." : "Jackett is connected and ready."
    }
    var enterSettings: String {
        language == .russian ? "Укажите адрес и API-ключ Jackett." : "Enter the Jackett address and API key."
    }
    var jackettSettings: String { language == .russian ? "Настройки Jackett" : "Jackett Settings" }
    var settingsHint: String {
        language == .russian
            ? "API-ключ находится в верхней части панели Jackett."
            : "The API key is shown near the top of the Jackett dashboard."
    }
    var openJackett: String { language == .russian ? "Открыть Jackett" : "Open Jackett" }
    var installJackett: String {
        language == .russian ? "Установить Jackett" : "Install Jackett"
    }
    var saveAndCheck: String {
        language == .russian ? "Сохранить и проверить" : "Save & Test"
    }
    var seeds: String { language == .russian ? "Сиды" : "Seeders" }
    var peers: String { language == .russian ? "Пиры" : "Peers" }
    var description: String { language == .russian ? "Описание" : "Description" }
    var noDescription: String {
        language == .russian
            ? "Этот трекер не передал описание. Название, размер и статистика раздачи всё равно доступны."
            : "This indexer did not provide a description. Release name, size, and swarm stats are still available."
    }
    var openSource: String { language == .russian ? "Открыть источник" : "Open Source" }
    var addToLibrary: String {
        language == .russian ? "Добавить в библиотеку" : "Add to Library"
    }
    var adding: String { language == .russian ? "Добавление…" : "Adding…" }
    var added: String { language == .russian ? "Добавлено" : "Added" }
    var startServerFirst: String {
        language == .russian
            ? "Сначала запустите TorrServer на вкладке «Сервер»."
            : "Start TorrServer from the Server tab first."
    }
    var couldNotAdd: String {
        language == .russian ? "Не удалось добавить раздачу" : "Could not add release"
    }
}

enum SearchFormat {
    static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}

extension View {
    @ViewBuilder
    func searchPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

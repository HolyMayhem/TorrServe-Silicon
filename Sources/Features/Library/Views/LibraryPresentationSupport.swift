import Foundation
import SwiftUI

struct LibraryTexts {
    let language: AppLanguage

    var library: String { language == .russian ? "Библиотека" : "Library" }
    var refresh: String { language == .russian ? "Обновить" : "Refresh" }
    var search: String { language == .russian ? "Поиск" : "Search" }
    var addMagnet: String { language == .russian ? "Добавить magnet-ссылку" : "Add magnet link" }
    var addTorrentFile: String { language == .russian ? "Добавить .torrent" : "Add .torrent" }
    var adding: String { language == .russian ? "Добавление…" : "Adding…" }
    var dropHint: String { language == .russian ? "Можно перетащить .torrent" : "Drop .torrent here" }
    var selectMaterial: String { language == .russian ? "Выберите материал" : "Select a material" }
    var selectMaterialHint: String {
        language == .russian
            ? "Здесь появятся файлы, статистика и кнопка запуска."
            : "Files, statistics, and playback controls will appear here."
    }
    var magnetHint: String {
        language == .russian
            ? "TorrServer получит метаданные и добавит материал в библиотеку."
            : "TorrServer will fetch metadata and add it to the library."
    }
    var cancel: String { language == .russian ? "Отмена" : "Cancel" }
    var add: String { language == .russian ? "Добавить" : "Add" }
    var serverUnavailable: String { language == .russian ? "TorrServer не запущен" : "TorrServer is stopped" }
    var startServerFirst: String {
        language == .russian
            ? "Сначала запустите сервер на вкладке «Сервер»."
            : "Start the server from the Server tab first."
    }
    var emptyLibrary: String { language == .russian ? "Библиотека пуста" : "Library is empty" }
    var emptyLibraryHint: String {
        language == .russian
            ? "Добавьте magnet-ссылку или torrent-файл."
            : "Add a magnet link or a torrent file."
    }
    var remove: String { language == .russian ? "Удалить" : "Remove" }
    func removeMaterialQuestion(count: Int) -> String {
        if count > 1 {
            return language == .russian ? "Удалить выбранные материалы?" : "Remove selected items?"
        }
        return language == .russian ? "Удалить материал?" : "Remove this item?"
    }
    func removeMaterialHint(count: Int) -> String {
        if count > 1 {
            return language == .russian
                ? "Выбранные материалы будут удалены из библиотеки TorrServer."
                : "The selected items will be removed from the TorrServer library."
        }
        return language == .russian
            ? "Материал будет удалён из библиотеки TorrServer."
            : "This item will be removed from the TorrServer library."
    }
    func selectedMaterialCount(_ count: Int) -> String {
        language == .russian
            ? "Выбрано материалов: \(count)"
            : "Selected items: \(count)"
    }
    var downloaded: String { language == .russian ? "Загружено" : "Downloaded" }
    var files: String { language == .russian ? "Файлы" : "Files" }
    var playerHint: String {
        language == .russian ? "Воспроизведение во внешнем плеере" : "Playback in an external player"
    }
    var metadataLoading: String {
        language == .russian ? "Получение метаданных torrent…" : "Fetching torrent metadata…"
    }
    var metadataProviderLoading: String {
        language == .russian ? "Получение метаданных…" : "Fetching metadata…"
    }
    var metadataIndicator: String {
        language == .russian ? "Метаданные" : "Metadata"
    }
    var metadataIndicatorLoading: String {
        language == .russian ? "загрузка" : "loading"
    }
    var metadataIndicatorMissing: String {
        language == .russian ? "нет" : "none"
    }
    var metadataIndicatorLoadingHint: String {
        language == .russian
            ? "Приложение сейчас ищет метаданные для этого материала."
            : "The app is currently looking up metadata for this item."
    }
    var metadataIndicatorMissingHint: String {
        language == .russian
            ? "Метаданные ещё не получены или материал не найден выбранным сервисом."
            : "Metadata has not been fetched yet or the selected service could not find this item."
    }
    func metadataIndicatorLoadedHint(_ provider: String) -> String {
        language == .russian
            ? "Метаданные успешно получены из \(provider)."
            : "Metadata was successfully loaded from \(provider)."
    }
    var seeds: String { language == .russian ? "Сиды" : "Seeds" }
    var peers: String { language == .russian ? "Пиры" : "Peers" }
    var watch: String { language == .russian ? "Смотреть" : "Watch" }
    var play: String { language == .russian ? "Воспроизвести" : "Play" }
    var buffering: String { language == .russian ? "Буферизация" : "Buffering" }
    var openInAnotherPlayer: String {
        language == .russian ? "Открыть в другом плеере" : "Open in another player"
    }
    var copyStreamURL: String {
        language == .russian ? "Скопировать stream URL" : "Copy stream URL"
    }
    var openSource: String {
        language == .russian ? "Открыть источник" : "Open source"
    }
    var showFiles: String {
        language == .russian ? "Показать файлы" : "Show files"
    }
    var refreshMetadata: String {
        language == .russian ? "Обновить метаданные" : "Refresh metadata"
    }

    func itemCount(_ count: Int) -> String {
        language == .russian ? "Материалов: \(count)" : "Items: \(count)"
    }

    func status(for torrent: NativeTorrent) -> String {
        switch torrent.stat {
        case 0:
            return language == .russian ? "Добавлен" : "Added"
        case 1:
            return language == .russian ? "Метаданные…" : "Metadata…"
        case 2:
            return language == .russian ? "Буферизация" : "Buffering"
        case 3:
            return language == .russian ? "Трансляция" : "Streaming"
        case 4:
            return language == .russian ? "Закрыт" : "Closed"
        case 5:
            return language == .russian ? "Готов" : "Ready"
        default:
            return torrent.statString.isEmpty ? "TorrServer" : torrent.statString
        }
    }
}

enum LibraryFormat {
    static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 KB/s" }
        return SpeedFormatter.string(
            bytesPerSecond: bytesPerSecond,
            unit: .automatic
        )
    }
}

extension View {
    @ViewBuilder
    func libraryPanel() -> some View {
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

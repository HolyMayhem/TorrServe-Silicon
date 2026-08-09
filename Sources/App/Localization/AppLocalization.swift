import Foundation

enum AppLanguage: String {
    case russian = "ru"
    case english = "en"

    static var systemDefault: AppLanguage {
        Locale.current.languageCode == "ru" ? .russian : .english
    }
}

struct Texts {
    let language: AppLanguage

    var about: String { language == .russian ? "О TorrServer" : "About TorrServer" }
    var quit: String { language == .russian ? "Завершить приложение" : "Quit" }
    var edit: String { language == .russian ? "Правка" : "Edit" }
    var undo: String { language == .russian ? "Отменить" : "Undo" }
    var redo: String { language == .russian ? "Повторить" : "Redo" }
    var cut: String { language == .russian ? "Вырезать" : "Cut" }
    var copy: String { language == .russian ? "Копировать" : "Copy" }
    var paste: String { language == .russian ? "Вставить" : "Paste" }
    var selectAll: String { language == .russian ? "Выбрать всё" : "Select All" }
    var title: String { "TorrServer" }
    var choose: String { language == .russian ? "Выбрать" : "Choose" }
    var downloadArm: String { language == .russian ? "Скачать ARM" : "Download ARM" }
    var start: String { language == .russian ? "Запустить" : "Start" }
    var stop: String { language == .russian ? "Остановить" : "Stop" }
    var webUI: String { language == .russian ? "Web UI" : "Web UI" }
    var openWebUI: String { language == .russian ? "Открыть Web UI" : "Open Web UI" }
    var showWindow: String { language == .russian ? "Показать окно" : "Show Window" }
    var downloadMenu: String {
        language == .russian
            ? "Скачать TorrServer для Apple Silicon"
            : "Download TorrServer for Apple Silicon"
    }
    var launchAtLogin: String {
        language == .russian ? "Открывать при входе в macOS" : "Open at Login"
    }
    var autoStartServer: String {
        language == .russian
            ? "Запускать сервер при открытии приложения"
            : "Start server when app opens"
    }
    var showSpeed: String {
        language == .russian
            ? "Показывать скорость в меню баре"
            : "Show speed in menu bar"
    }
    var notifications: String {
        language == .russian ? "Системные уведомления" : "System notifications"
    }
    var jackettSearch: String {
        language == .russian ? "Поиск" : "Search"
    }
    var metadataProvider: String {
        language == .russian ? "Источник метаданных" : "Metadata source"
    }
    var metadataAPIKey: String {
        "API Key"
    }
    var metadataConfigure: String {
        language == .russian ? "Настроить" : "Configure"
    }
    var metadataConfigured: String {
        language == .russian ? "Подключено" : "Connected"
    }
    var speedFormat: String {
        language == .russian ? "Формат скорости" : "Speed format"
    }
    var automaticSpeed: String { language == .russian ? "Авто" : "Auto" }
    var megabytesSpeed: String { "MB/s" }
    var megabitsSpeed: String { "Mbit/s" }
    var hideDockIcon: String {
        language == .russian
            ? "Показывать приложение только в меню баре"
            : "Show app in menu bar only"
    }
    var playerHelpTitle: String {
        language == .russian ? "Плееры для просмотра" : "Playback apps"
    }
    var playerHelpMessage: String {
        language == .russian
            ? "Приложение автоматически проверяет IINA, VLC и Infuse. Нажмите установленный плеер, чтобы выбрать его."
            : "The app automatically checks IINA, VLC, and Infuse. Select any installed player to make it the default."
    }
    var storageDescription: String {
        language == .russian
            ? "Буфер TorrServer, дисковый кеш и доступное место."
            : "TorrServer buffer, disk cache, and available storage."
    }
    var languageLabel: String { language == .russian ? "Язык" : "Language" }
    var russian: String { "Russian" }
    var english: String { "English" }
    var stopped: String { language == .russian ? "Остановлен" : "Stopped" }
    var chooseOrDownload: String {
        language == .russian ? "Выберите или скачайте TorrServer" : "Choose or download TorrServer"
    }
    var torrServerNotSelected: String {
        language == .russian ? "TorrServer не выбран" : "TorrServer is not selected"
    }
    func running(pid: Int32) -> String {
        language == .russian ? "Работает · PID \(pid)" : "Running · PID \(pid)"
    }
    var stopping: String { language == .russian ? "Останавливается…" : "Stopping…" }
    var downloading: String {
        language == .russian ? "Скачивается TorrServer…" : "Downloading TorrServer…"
    }
    var launchError: String { language == .russian ? "Ошибка запуска" : "Launch Error" }
    func error(_ message: String) -> String {
        language == .russian ? "Ошибка: \(message)" : "Error: \(message)"
    }
    func errorTooltip(_ message: String) -> String {
        if language == .russian {
            return """
            TorrServer неожиданно завершил работу.

            \(message)

            Возможные причины: порт 8090 уже занят другой копией TorrServer, \
            исполняемый файл повреждён или macOS запретила его запуск.
            """
        }

        return """
        TorrServer stopped unexpectedly.

        \(message)

        Possible causes: port 8090 is already used by another TorrServer process, \
        the executable is damaged, or macOS blocked it from launching.
        """
    }
    var speedLabel: String { language == .russian ? "Скорость" : "Speed" }
    var speedOff: String { language == .russian ? "выключена" : "off" }
    var speedNoData: String { language == .russian ? "нет данных" : "no data" }
    var materialsTitle: String { language == .russian ? "Материалы" : "Materials" }
    var currentMaterial: String {
        language == .russian ? "Сейчас транслируется" : "Now streaming"
    }
    var recentMaterial: String {
        language == .russian ? "Последний материал" : "Latest material"
    }
    var noActiveMaterial: String {
        language == .russian ? "Нет активной трансляции" : "No active stream"
    }
    var buffer: String { language == .russian ? "Буфер" : "Buffer" }
    var seeds: String { language == .russian ? "Сиды" : "Seeds" }
    var peers: String { language == .russian ? "Пиры" : "Peers" }
    var speedHistory: String {
        language == .russian ? "Скорость за 60 секунд" : "Speed over 60 seconds"
    }
    var localWebUI: String {
        language == .russian ? "Web UI в локальной сети" : "Web UI on local network"
    }
    var showQRCode: String {
        language == .russian ? "Показать QR-код" : "Show QR code"
    }
    var hideQRCode: String {
        language == .russian ? "Скрыть QR-код" : "Hide QR code"
    }
    var openWindow: String {
        language == .russian ? "Открыть приложение" : "Open app"
    }
    var serverStartedNotificationTitle: String {
        language == .russian ? "TorrServer запущен" : "TorrServer started"
    }
    var serverStartedNotificationMessage: String {
        language == .russian
            ? "Сервер готов к работе на порту 8090."
            : "The server is ready on port 8090."
    }
    var updateInstalledNotificationTitle: String {
        language == .russian ? "Обновление установлено" : "Update installed"
    }
    var errorNotificationTitle: String {
        language == .russian ? "Ошибка TorrServer" : "TorrServer error"
    }
    var loadingMaterials: String { language == .russian ? "Загрузка…" : "Loading…" }
    var noMaterials: String { language == .russian ? "Нет материалов" : "No materials" }
    func moreMaterials(_ count: Int) -> String {
        language == .russian ? "Еще \(count)…" : "\(count) more…"
    }
    var seedsShort: String { "S" }
    var peersShort: String { "P" }
    var choosePanelTitle: String {
        language == .russian
            ? "Выберите исполняемый файл TorrServer"
            : "Choose TorrServer executable"
    }
    var choosePanelMessage: String {
        language == .russian
            ? "Обычно файл называется TorrServer или TorrServer-darwin-arm64."
            : "The file is usually named TorrServer or TorrServer-darwin-arm64."
    }
    var choosePanelPrompt: String { language == .russian ? "Выбрать" : "Choose" }
    var chooseTorrServerAlertTitle: String {
        language == .russian ? "Выберите TorrServer" : "Choose TorrServer"
    }
    var chooseTorrServerAlertMessage: String {
        language == .russian
            ? "Сначала выберите файл вручную или скачайте последнюю версию для Apple Silicon."
            : "Choose the executable manually or download the latest Apple Silicon version first."
    }
    var startFailedTitle: String {
        language == .russian ? "TorrServer не запущен" : "TorrServer did not start"
    }
    var downloadDoneTitle: String {
        language == .russian ? "TorrServer скачан" : "TorrServer downloaded"
    }
    var downloadDoneMessage: String {
        language == .russian
            ? "Файл сохранен и выбран автоматически."
            : "The file was saved and selected automatically."
    }
    var downloadFailedTitle: String {
        language == .russian ? "Не удалось скачать TorrServer" : "Could not download TorrServer"
    }
    var launchAtLoginFailedTitle: String {
        language == .russian ? "Автозапуск не изменен" : "Open at Login was not changed"
    }
    var aboutCredits: String {
        "Created for Holy Mayhem\nNative macOS GUI for TorrServer"
    }
}

import Foundation

enum TorrentAddError: LocalizedError {
    case missingLink
    case invalidLink
    case downloadNetwork(Int)
    case downloadHTTP(Int)
    case invalidRedirect
    case redirectLimit
    case unsafeRedirect
    case invalidTorrent(TorrentFileError)
    case transferNetwork(Int)
    case transferHTTP(Int)
    case unexpectedResponse
    case noAddedTorrent

    var diagnostic: (stage: String, category: String, code: Int) {
        switch self {
        case .missingLink: return ("link", "missing", 0)
        case .invalidLink: return ("link", "invalid", 0)
        case .downloadNetwork(let code): return ("download", "network", code)
        case .downloadHTTP(let code): return ("download", "http", code)
        case .invalidRedirect: return ("redirect", "invalid", 0)
        case .redirectLimit: return ("redirect", "limit", 0)
        case .unsafeRedirect: return ("redirect", "credentials_or_scheme", 0)
        case .invalidTorrent(let reason): return ("validation", reason.rawValue, 0)
        case .transferNetwork(let code): return ("transfer", "network", code)
        case .transferHTTP(let code): return ("transfer", "http", code)
        case .unexpectedResponse: return ("server_response", "invalid", 0)
        case .noAddedTorrent: return ("server_response", "empty", 0)
        }
    }

    var errorDescription: String? { message(language: .systemDefault) }

    func message(language: AppLanguage, source: String? = nil) -> String {
        let ru = language == .russian
        let source = source ?? (ru ? "Источник поиска" : "Search source")
        switch self {
        case .missingLink:
            return ru ? "\(source) не предоставил ссылку на раздачу." : "\(source) did not provide a download link."
        case .invalidLink:
            return ru ? "\(source) предоставил некорректную ссылку на раздачу." : "\(source) provided an invalid download link."
        case .downloadNetwork(let code):
            return ru ? "Сбой сети при скачивании через \(source) (код \(code))." : "Network error while downloading via \(source) (code \(code))."
        case .downloadHTTP(let status):
            return ru ? "\(source) вернул HTTP \(status) при скачивании." : "\(source) returned HTTP \(status) during download."
        case .invalidRedirect:
            return ru ? "\(source) вернул некорректное перенаправление." : "\(source) returned an invalid download redirect."
        case .redirectLimit:
            return ru ? "Слишком много перенаправлений при скачивании через \(source)." : "Too many redirects while downloading via \(source)."
        case .unsafeRedirect:
            return ru ? "Перенаправление при скачивании через \(source) небезопасно." : "The download redirect from \(source) was unsafe."
        case .invalidTorrent(let reason):
            switch reason {
            case .html:
                return ru ? "Вместо .torrent получена веб-страница. Возможно, источник требует входа." : "Received a web page instead of a .torrent file. The source may require sign-in."
            case .json, .xml:
                return ru ? "Вместо .torrent получен ответ \(reason.rawValue.uppercased())." : "Received a \(reason.rawValue.uppercased()) response instead of a .torrent file."
            case .empty:
                return ru ? "Получен пустой .torrent-файл." : "Received an empty .torrent file."
            case .missingInfo:
                return ru ? "В .torrent отсутствует словарь info с данными раздачи." : "The .torrent file is missing its info dictionary."
            case .bencode:
                return ru ? "Получен некорректный .torrent-файл (Bencode)." : "The .torrent file contains invalid Bencode."
            }
        case .transferNetwork(let code):
            return ru ? "Сбой сети при передаче раздачи в TorrServer (код \(code))." : "Network error while sending the torrent to TorrServer (code \(code))."
        case .transferHTTP(let status):
            return ru ? "TorrServer отклонил добавление раздачи (HTTP \(status))." : "TorrServer rejected the add request (HTTP \(status))."
        case .unexpectedResponse:
            return ru ? "TorrServer вернул неожиданный ответ при добавлении раздачи." : "TorrServer returned an unexpected response to the add request."
        case .noAddedTorrent:
            return ru ? "TorrServer не вернул добавленную раздачу." : "TorrServer did not return an added torrent."
        }
    }
}

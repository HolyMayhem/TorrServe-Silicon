import OSLog
import SwiftUI

struct CatalogUnavailableView: View {
    let attempts: [CatalogLoadFailure.Attempt]
    let text: CatalogText
    let retry: () -> Void

    private static let logger = Logger(subsystem: "com.holymayhem.torrserver", category: "Catalog")

    var body: some View {
        ContentUnavailableView {
            Label(text("Couldn’t load the catalog", "Не удалось загрузить каталог"), systemImage: "film")
        } description: {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach([CatalogSource.tmdb, .cub], id: \.self) { source in
                    let reasons = attempts.filter { $0.source == source }.map { message($0.reason) }
                    ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(source == .tmdb ? "TMDB" : "CUB")
                                .fontWeight(.medium)
                                .opacity(index == 0 ? 1 : 0)
                                .accessibilityHidden(index != 0)
                            Text(reason)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.top, 6)
        } actions: {
            Button(action: retry) {
                Label(text("Retry", "Повторить"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("catalog-unavailable")
        .task(id: attempts) {
            for attempt in attempts {
                Self.logger.error("Catalog load failed. source=\(attempt.source.rawValue, privacy: .public) reason=\(String(describing: attempt.reason), privacy: .public)")
            }
        }
    }

    private func message(_ reason: CatalogLoadFailure.Reason) -> String {
        switch reason {
        case .simulated:
            text("Outage simulated in Developer settings", "Включена имитация недоступности")
        case .offline:
            text("No internet connection", "Нет подключения к интернету")
        case .dns:
            text("Couldn’t find the server address (DNS)", "Не удалось найти адрес сервера (DNS)")
        case .connection:
            text("Couldn’t connect to the server", "Не удалось установить соединение")
        case .timeout:
            text("The server took too long to respond", "Сервер не ответил вовремя")
        case .secureConnection:
            text("Couldn’t establish a secure connection", "Не удалось установить защищённое соединение")
        case .missingKey:
            text("API key is missing", "Отсутствует ключ API")
        case .invalidRequest:
            text("Couldn’t create the request", "Не удалось сформировать запрос")
        case .accessDenied(let code):
            text("Access denied (HTTP \(code))", "Доступ отклонён (HTTP \(code))")
        case .rateLimited:
            text("Too many requests (HTTP 429)", "Слишком много запросов (HTTP 429)")
        case .serviceError(let code):
            text("Server error (HTTP \(code))", "Ошибка на стороне сервера (HTTP \(code))")
        case .unexpectedHTTPStatus(let code):
            text("Unexpected server status (HTTP \(code))", "Неожиданный статус сервера (HTTP \(code))")
        case .invalidResponse:
            text("Couldn’t read the server response", "Не удалось прочитать ответ сервера")
        case .otherNetworkError(let code):
            text("Network error (code \(code))", "Ошибка сети (код \(code))")
        case .unknown:
            text("Couldn’t determine the cause", "Не удалось определить причину")
        }
    }
}

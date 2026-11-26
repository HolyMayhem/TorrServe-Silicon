import Foundation
#if canImport(OSLog)
import OSLog
#endif

enum TorrentAddDiagnostics {
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.holymayhem.torrserver", category: "TorrentAdd")
    #endif

    static func event(stage: String, source: String, link: String, status: Int = 0) {
        #if canImport(OSLog)
        logger.notice("stage=\(stage, privacy: .public) source=\(source, privacy: .public) link=\(link, privacy: .public) http=\(status, privacy: .public)")
        #endif
    }

    static func failure(_ error: TorrentAddError, source: String, link: String) {
        #if canImport(OSLog)
        let detail = error.diagnostic
        logger.error("result=failed stage=\(detail.stage, privacy: .public) source=\(source, privacy: .public) link=\(link, privacy: .public) category=\(detail.category, privacy: .public) code=\(detail.code, privacy: .public)")
        #endif
    }
}

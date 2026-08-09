import Foundation

enum DiagnosticResultKind: Equatable {
    case idle
    case checking
    case success
    case warning
    case failure
}

struct DiagnosticResult: Equatable {
    let kind: DiagnosticResultKind
    let message: String

    static let idle = DiagnosticResult(kind: .idle, message: "")
}

enum DiagnosticProcessKind: Equatable {
    case application
    case server
    case portOwner

    func title(language: AppLanguage) -> String {
        switch self {
        case .application:
            return language == .russian ? "копия приложения" : "app copy"
        case .server:
            return language == .russian ? "процесс TorrServer" : "TorrServer process"
        case .portOwner:
            return language == .russian ? "владелец порта 8090" : "port 8090 owner"
        }
    }
}

struct DiagnosticProcessInfo: Identifiable, Equatable {
    let pid: Int32
    let parentPID: Int32
    let executableName: String
    let command: String
    let kind: DiagnosticProcessKind
    let listensOnPort8090: Bool

    var id: Int32 { pid }
}

struct TorrServerProcessScan: Equatable {
    let result: DiagnosticResult
    let processes: [DiagnosticProcessInfo]
    let listenerPIDs: [Int32]

    static let empty = TorrServerProcessScan(
        result: .idle,
        processes: [],
        listenerPIDs: []
    )
}

struct TorrServerStorageSnapshot: Equatable {
    var cacheUsed: Int64 = 0
    var cacheCapacity: Int64 = 0
    var diskCacheSize: Int64 = 0
    var freeDiskSpace: Int64 = 0
    var diskCacheEnabled = false
    var diskCachePath = ""

    var isLowOnDiskSpace: Bool {
        freeDiskSpace > 0 && freeDiskSpace < 10 * 1024 * 1024 * 1024
    }
}

import SwiftUI

enum MainStatusKind: Equatable {
    case stopped
    case running
    case working
    case failed

    var color: Color {
        switch self {
        case .stopped:
            return .secondary
        case .running:
            return .green
        case .working:
            return .orange
        case .failed:
            return .red
        }
    }
}

final class MainWindowModel: ObservableObject {
    @Published var path = ""
    @Published var language: AppLanguage = .systemDefault
    @Published var statusText = ""
    @Published var statusTooltip = ""
    @Published var statusKind: MainStatusKind = .stopped
    @Published var currentSpeedText = ""

    @Published var canStart = false
    @Published var canStop = false
    @Published var canBrowse = true
    @Published var canDownload = true
    @Published var canOpenWeb = true
    @Published var canEditPath = true

    @Published var launchAtLogin = false
    @Published var autoStartServer = false
    @Published var showSpeed = true
    @Published var hideDockIcon = false
    @Published var notificationsEnabled = false
    @Published var notificationsAuthorizationPending = false
    @Published var jackettEnabled = true
    @Published var metadataProvider = MetadataProvider.tmdb
    @Published var tmdbAPIKey = ""
    @Published var omdbAPIKey = ""
    @Published var overviewTranslationMode = OverviewTranslationMode.automatic
    @Published var speedUnit: SpeedDisplayUnit = .automatic
    @Published var selectedSection: AppSection = .library
    @Published var detectedPlayers: [DetectedPlayer] = []
    @Published var preferredPlayer: ExternalPlayerChoice = .quickTime
    @Published var storage = TorrServerStorageSnapshot()
    @Published var isRefreshingStorage = false
    @Published var isClearingCache = false
    @Published var isRunningDiagnostics = false
    @Published var isStoppingExternalProcesses = false
    @Published var portDiagnostic = DiagnosticResult.idle
    @Published var processDiagnostic = DiagnosticResult.idle
    @Published var processScan = TorrServerProcessScan.empty
    @Published var executableDiagnostic = DiagnosticResult.idle
    @Published var latestDiagnostic = DiagnosticResult.idle

    var onPathChanged: ((String) -> Void)?
    var onChoose: (() -> Void)?
    var onDownload: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenContacts: (() -> Void)?
    var onOpenWeb: (() -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAutoStartChanged: ((Bool) -> Void)?
    var onShowSpeedChanged: ((Bool) -> Void)?
    var onHideDockIconChanged: ((Bool) -> Void)?
    var onNotificationsChanged: ((Bool) -> Void)?
    var onJackettEnabledChanged: ((Bool) -> Void)?
    var onMetadataProviderChanged: ((MetadataProvider) -> Void)?
    var onMetadataAPIKeyChanged: ((MetadataProvider, String) -> Void)?
    var onOverviewTranslationModeChanged: ((OverviewTranslationMode) -> Void)?
    var onSpeedUnitChanged: ((SpeedDisplayUnit) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onSectionChanged: ((AppSection) -> Void)?
    var onOpenIINADownload: (() -> Void)?
    var onOpenVLCDownload: (() -> Void)?
    var onOpenInfuseDownload: (() -> Void)?
    var onSelectPlayer: ((ExternalPlayerChoice) -> Void)?
    var onRefreshStorage: (() -> Void)?
    var onClearCache: (() -> Void)?
    var onCheckPort: (() -> Void)?
    var onFindTorrServer: (() -> Void)?
    var onRunFullDiagnostics: (() -> Void)?
    var onStopExternalProcesses: (() -> Void)?
    var onCheckExecutable: (() -> Void)?
    var onCopyDiagnosticReport: (() -> Void)?
    var onSaveDiagnosticReport: (() -> Void)?
}

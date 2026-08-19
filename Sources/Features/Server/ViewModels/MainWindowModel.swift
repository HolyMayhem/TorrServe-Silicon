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

enum MetadataAPIKeyTestState: Equatable {
    case idle
    case testing
    case valid
    case invalid
    case rateLimited
    case unavailable
}

final class MainWindowModel: ObservableObject {
    @Published var path = ""
    @Published var language: AppLanguage = .systemDefault
    @Published var statusText = ""
    @Published var statusTooltip = ""
    @Published var statusKind: MainStatusKind = .stopped
    @Published var serverConnectionIssue: String?
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
    @Published var metadataSource = MetadataSourceMode.tmdb
    @Published var metadataAPIKeyMode = MetadataAPIKeyMode.builtIn
    @Published var combinedMetadataOrder = MetadataProviderSettings.defaultCombinedOrder
    @Published var tmdbAPIKey = ""
    @Published var omdbAPIKey = ""
    @Published var kinopoiskAPIKey = ""
    @Published var metadataAPIKeyTestStates: [MetadataProvider: MetadataAPIKeyTestState] = [:]
    @Published var metadataKeysDiagnostic = DiagnosticResult.idle
    @Published var isTestingAllMetadataAPIKeys = false
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
    @Published var serverSettingsDraft = TorrServerSettingsDraft.defaults
    @Published var savedServerSettingsDraft = TorrServerSettingsDraft.defaults
    @Published var serverSettingsResult = DiagnosticResult.idle
    @Published var isLoadingServerSettings = false
    @Published var isSavingServerSettings = false
    @Published var hasLoadedServerSettings = false

    var effectiveStatusKind: MainStatusKind {
        serverConnectionIssue == nil ? statusKind : .failed
    }

    var hasUnsavedServerSettings: Bool {
        hasLoadedServerSettings
            && serverSettingsDraft.normalized != savedServerSettingsDraft.normalized
    }

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
    var onMetadataSourceChanged: ((MetadataSourceMode) -> Void)?
    var onMetadataAPIKeyModeChanged: ((MetadataAPIKeyMode) -> Void)?
    var onCombinedMetadataOrderChanged: (([MetadataProvider]) -> Void)?
    var onMetadataAPIKeyChanged: ((MetadataProvider, String) -> Void)?
    var onTestMetadataAPIKey: ((MetadataProvider, String) -> Void)?
    var onTestAllMetadataAPIKeys: (() -> Void)?
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
    var onLoadServerSettings: (() -> Void)?
    var onSaveServerSettings: (() -> Void)?
    var onChooseServerCacheFolder: (() -> Void)?
}

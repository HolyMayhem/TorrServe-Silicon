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

struct TorrServerUpdateActivity: Equatable {
    enum Kind: Equatable {
        case download
        case update
    }

    enum Stage: Equatable {
        case preparing
        case downloading
        case installing
        case restarting
        case completed
    }

    let kind: Kind
    let stage: Stage
    let progress: Double
    let targetVersion: String?

    var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    func title(language: AppLanguage) -> String {
        switch stage {
        case .completed:
            return language == .russian ? "Готово" : "Complete"
        case .preparing, .downloading, .installing, .restarting:
            switch kind {
            case .download:
                return language == .russian ? "Скачивается" : "Downloading"
            case .update:
                return language == .russian ? "Обновляется" : "Updating"
            }
        }
    }

    func detail(language: AppLanguage) -> String {
        let version = targetVersion.map { " \($0)" } ?? ""
        switch stage {
        case .preparing:
            return language == .russian
                ? "Подготовка загрузки\(version)…"
                : "Preparing\(version)…"
        case .downloading:
            let percentage = Int((clampedProgress * 100).rounded())
            return language == .russian
                ? "Загрузка\(version) · \(percentage)%"
                : "Downloading\(version) · \(percentage)%"
        case .installing:
            return language == .russian
                ? "Установка\(version)…"
                : "Installing\(version)…"
        case .restarting:
            return language == .russian
                ? "Перезапуск TorrServer…"
                : "Restarting TorrServer…"
        case .completed:
            if let targetVersion {
                return language == .russian
                    ? "\(targetVersion) установлена"
                    : "\(targetVersion) installed"
            }
            return language == .russian
                ? "TorrServer установлен"
                : "TorrServer installed"
        }
    }
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
    @Published var torrServerVersion: String?
    @Published var torrServerUpdate: TorrServerAvailableUpdate?
    @Published var torrServerUpdateActivity: TorrServerUpdateActivity?

    @Published var launchAtLogin = false
    @Published var autoStartServer = false
    @Published var autoUpdateTorrServer = false
    @Published var menuBarPreferences = MenuBarPreferences.defaults
    @Published var hideDockIcon = false
    @Published var notificationsEnabled = false
    @Published var notificationsAuthorizationPending = false
    @Published var jackettEnabled = true
    @Published var metadataSource = MetadataSourceMode.tmdb
    @Published var aniListEnabled = true
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
    var onInstallTorrServerUpdate: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenContacts: (() -> Void)?
    var onOpenWeb: (() -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAutoStartChanged: ((Bool) -> Void)?
    var onAutoUpdateTorrServerChanged: ((Bool) -> Void)?
    var onMenuBarPreferencesChanged: ((MenuBarPreferences) -> Void)?
    var onHideDockIconChanged: ((Bool) -> Void)?
    var onNotificationsChanged: ((Bool) -> Void)?
    var onJackettEnabledChanged: ((Bool) -> Void)?
    var onOpenJackettDashboard: (() -> Void)?
    var onMetadataSourceChanged: ((MetadataSourceMode) -> Void)?
    var onAniListEnabledChanged: ((Bool) -> Void)?
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

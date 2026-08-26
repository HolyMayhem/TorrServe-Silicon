import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import QuartzCore
import Security
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

let savedPathKey = "TorrServerExecutablePath"
let autoStartServerKey = "AutoStartServerOnLaunch"
let autoUpdateTorrServerKey = "AutoUpdateTorrServer"
let showSpeedInMenuBarKey = "ShowSpeedInMenuBar"
let hideDockIconKey = "HideDockIcon"
let languageKey = "AppLanguage"
let speedDisplayUnitKey = "SpeedDisplayUnit"
let jackettSearchEnabledKey = "JackettSearchEnabled"
let productionBundleIdentifier = "com.holymayhem.torrserver"
let legacyBundleIdentifier = "local.codex.torrserver-manager"
let preferencesMigrationKey = "MigratedPreferencesFromLocalCodex"

func migrateLegacyPreferencesIfNeeded() {
    guard Bundle.main.bundleIdentifier == productionBundleIdentifier else { return }

    let current = UserDefaults.standard
    guard !current.bool(forKey: preferencesMigrationKey) else { return }

    if let legacy = UserDefaults(suiteName: legacyBundleIdentifier) {
        let keys = [
            savedPathKey,
            autoStartServerKey,
            autoUpdateTorrServerKey,
            showSpeedInMenuBarKey,
            MenuBarPreferencesStore.Key.iconVisible,
            MenuBarPreferencesStore.Key.recentMaterial,
            MenuBarPreferencesStore.Key.quickActions,
            MenuBarPreferencesStore.Key.qrCode,
            MenuBarPreferencesStore.Key.expandQRCode,
            MenuBarPreferencesStore.Key.sectionOrder,
            hideDockIconKey,
            languageKey,
            speedDisplayUnitKey,
            jackettSearchEnabledKey,
            "JackettServerURL",
            "JackettAPIKey",
            "LibraryPreferredPlayer",
            "LibraryCustomPlayerPath",
            "LibraryPlayerSetupCompleted",
            "LibraryDisplayMode",
            "LibraryMetadataByTorrentHash"
        ]

        for key in keys where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
    }

    current.set(true, forKey: preferencesMigrationKey)
}








@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let processController = TorrServerProcessController()
    let downloader = TorrServerDownloader()
    let launchAtLoginController = LaunchAtLoginController()
    let speedMonitor = TorrServerSpeedMonitor()
    let notificationController = NotificationController()
    let releaseChecker = TorrServerReleaseChecker()
    let nativeTorrServerAPI = NativeTorrServerAPI()
    lazy var diagnosticsService = TorrServerDiagnosticsService(api: nativeTorrServerAPI)
    let metadataAPIKeyValidator = MetadataAPIKeyValidator()
    let metadataSettings = MetadataSettingsStore.shared
    let menuBarPreferencesStore = MenuBarPreferencesStore()
    let mainWindowModel = MainWindowModel()
    lazy var libraryModel = LibraryViewModel(api: nativeTorrServerAPI)
    lazy var searchModel = SearchViewModel(torrServer: nativeTorrServerAPI)
    let popoverModel = MenuBarPopoverModel()

    var window: NSWindow!
    var serverContentSize = NSSize(width: 580, height: 500)

    var statusItem: NSStatusItem!
    var statusPopover: NSPopover!
    var menuBarMaterialTimer: Timer?
    var torrServerUpdateTimer: Timer?
    var torrServerUpdateWorkItem: DispatchWorkItem?
    var torrServerUpdateCheckRevision = 0
    var localPopoverEventMonitor: Any?
    var globalPopoverEventMonitor: Any?

    var isDownloading = false
    var hasRepliedToTermination = false
    var currentSpeedBytesPerSecond: Double?
    var currentTorrents: [NativeTorrent] = []
    var speedHistory: [Double] = []
    var hasAnnouncedRunningState = false
    var diagnosticsRevision = 0
    var isNotificationAuthorizationPending = false
    var loadedTorrServerSettings: TorrServerStorageSettings?
    var consecutiveServerConnectionFailures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaultSettings()
        launchAtLoginController.migrateLegacyAgentIfNeeded()
        applyActivationPolicy()
        buildMainMenu()
        buildStatusItem()
        buildWindow()
        applyLanguage()
        notificationController.synchronizeEnabledState { [weak self] enabled in
            self?.mainWindowModel.notificationsEnabled = enabled
        }

        processController.onStateChange = { [weak self] state in
            self?.handleNotification(for: state)
            self?.updateUI(for: state)
        }
        speedMonitor.onSpeedChange = { [weak self] speed in
            self?.recordSpeedSample(speed)
        }
        updateUI(for: .stopped)
        refreshPlayerAvailability()
        refreshStorage()
        checkForTorrServerUpdate()
        schedulePeriodicTorrServerUpdateChecks()

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if UserDefaults.standard.bool(forKey: autoStartServerKey), hasExecutablePath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startServer(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleTorrServerUpdateCheck()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard processController.isRunning else {
            return .terminateNow
        }

        guard !hasRepliedToTermination else {
            return .terminateLater
        }

        processController.stop { [weak self, weak sender] in
            guard let self, !self.hasRepliedToTermination else { return }
            self.hasRepliedToTermination = true
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

}

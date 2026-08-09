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
            showSpeedInMenuBarKey,
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
    enum MenuBarVisualState {
        case stopped
        case running
        case streaming
        case working
        case buffering
        case failed
        case updating
    }
    let processController = TorrServerProcessController()
    let downloader = TorrServerDownloader()
    let launchAtLoginController = LaunchAtLoginController()
    let speedMonitor = TorrServerSpeedMonitor()
    let libraryClient = TorrServerLibraryClient()
    let notificationController = NotificationController()
    let diagnosticsService = TorrServerDiagnosticsService()
    let metadataSettings = MetadataSettingsStore.shared
    let mainWindowModel = MainWindowModel()
    let libraryModel = LibraryViewModel()
    let searchModel = SearchViewModel()
    let popoverModel = MenuBarPopoverModel()

    var window: NSWindow!
    var serverContentSize = NSSize(width: 580, height: 500)

    var statusItem: NSStatusItem!
    var statusPopover: NSPopover!
    var popoverRefreshTimer: Timer?
    var menuBarMaterialTimer: Timer?
    var menuBarAnimationTimer: Timer?
    var localPopoverEventMonitor: Any?
    var globalPopoverEventMonitor: Any?

    var isDownloading = false
    var hasRepliedToTermination = false
    var currentSpeedBytesPerSecond: Double?
    var currentStatusIconColor: NSColor = .systemGray
    var currentTorrents: [TorrentSummary] = []
    var speedHistory: [Double] = []
    var hasAnnouncedRunningState = false
    var menuBarAnimationPhase: CGFloat = 0
    var diagnosticsRevision = 0
    var isNotificationAuthorizationPending = false

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

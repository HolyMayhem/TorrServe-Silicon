import AppKit
import SwiftUI

/// A uniform rounded surface without the titlebar's different lower corners.
private final class WhatsNewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    private let history: WhatsNewHistory
    private let resourceURL: URL?
    private let hadPreviousInstallation: Bool
    private var appVersion = "—"
    private var pendingAutomaticPresentation = false
    private var acknowledgesOnContinue = false
    private weak var parentWindow: NSWindow?
    private var languageProvider: (() -> String)?
    private(set) var manifest: WhatsNewManifest?
    private(set) var loadError: String?
    private(set) var presentedWindow: NSWindow?

    init(
        defaults: UserDefaults = .standard,
        resourceURL: URL? = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
        hadPreviousInstallation: Bool? = nil
    ) {
        history = WhatsNewHistory(defaults: defaults)
        self.resourceURL = resourceURL
        self.hadPreviousInstallation = hadPreviousInstallation
            ?? WhatsNewHistory.hasPreviousInstallation(defaults: defaults, bundleIdentifier: Bundle.main.bundleIdentifier)
        super.init()
    }

    func prepareLaunch(currentBuild: Int, appVersion: String) {
        self.appVersion = appVersion
        do {
            guard let resourceURL else {
                loadError = "WhatsNew.json is not bundled. Build the .app using scripts/build-app.sh."
                pendingAutomaticPresentation = history.prepareLaunch(
                    currentBuild: currentBuild, manifest: nil, hadPreviousInstallation: hadPreviousInstallation
                )
                return
            }
            manifest = try WhatsNewManifest.load(data: Data(contentsOf: resourceURL))
            loadError = nil
        } catch {
            manifest = nil
            loadError = error.localizedDescription
        }
        pendingAutomaticPresentation = history.prepareLaunch(
            currentBuild: currentBuild, manifest: manifest, hadPreviousInstallation: hadPreviousInstallation
        )
    }

    func observePresentationOpportunities(parent: NSWindow, language: @escaping () -> String) {
        parentWindow = parent
        languageProvider = language
        let center = NotificationCenter.default
        center.removeObserver(self)
        center.addObserver(self, selector: #selector(presentationOpportunity(_:)), name: NSApplication.didBecomeActiveNotification, object: NSApp)
        center.addObserver(self, selector: #selector(presentationOpportunity(_:)), name: NSWindow.didBecomeKeyNotification, object: parent)
        center.addObserver(self, selector: #selector(presentationOpportunity(_:)), name: NSWindow.didEndSheetNotification, object: parent)
        DispatchQueue.main.async { [weak self] in self?.presentAutomaticallyIfPossible() }
    }

    @objc private func presentationOpportunity(_ notification: Notification) {
        presentAutomaticallyIfPossible()
    }

    private func presentAutomaticallyIfPossible() {
        guard pendingAutomaticPresentation, presentedWindow == nil,
              NSApp.isActive, let parentWindow, parentWindow.isVisible,
              NSApp.keyWindow === parentWindow, parentWindow.attachedSheet == nil,
              NSApp.modalWindow == nil else { return }
        present(languageCode: languageProvider?() ?? "en", relativeTo: parentWindow, acknowledge: true)
    }

    @discardableResult
    func preview(languageCode: String, relativeTo parent: NSWindow?) -> Bool {
        guard manifest != nil else { return false }
        if let presentedWindow {
            presentedWindow.makeKeyAndOrderFront(nil)
        } else {
            present(languageCode: languageCode, relativeTo: parent, acknowledge: false)
        }
        return true
    }

    private func present(languageCode: String, relativeTo parent: NSWindow?, acknowledge: Bool) {
        guard let manifest else { return }
        let content = WhatsNewView(
            manifest: manifest, languageCode: languageCode, appVersion: appVersion,
            onContinue: { [weak self] in self?.continuePresentation() },
            onShowDetails: {
                if let url = manifest.detailsURL { NSWorkspace.shared.open(url) }
            }
        )
        let available = (parent?.screen ?? NSScreen.main)?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        var width = min(600, available.width - 48)
        let maximumWidth = min(900, available.width - 48)
        let hostingView = NSHostingView(rootView: content.frame(width: width))
        var height = ceil(hostingView.fittingSize.height)
        // Measure the localized content, including every feature and both buttons.
        // Wider text columns can also keep longer announcements within a small screen.
        while height > available.height - 48, width < maximumWidth {
            width = min(width + 60, maximumWidth)
            hostingView.rootView = content.frame(width: width)
            height = ceil(hostingView.fittingSize.height)
        }
        let size = NSSize(width: width, height: height)
        let window = WhatsNewWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.title = manifest.content(languageCode: languageCode).title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.tabbingMode = .disallowed
        window.delegate = self
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        window.contentMinSize = size
        window.contentMaxSize = size
        acknowledgesOnContinue = acknowledge
        presentedWindow = window
        window.contentView = hostingView
        window.setContentSize(size)
        if let parent {
            let frame = NSRect(x: parent.frame.midX - window.frame.width / 2,
                               y: parent.frame.midY - window.frame.height / 2,
                               width: window.frame.width, height: window.frame.height)
            window.setFrame(window.constrainFrameRect(frame, to: parent.screen), display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func continuePresentation() {
        guard let window = presentedWindow else { return }
        if acknowledgesOnContinue, let manifest {
            history.acknowledge(manifest.id)
            pendingAutomaticPresentation = false
        }
        presentedWindow = nil
        acknowledgesOnContinue = false
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Continue is the single acknowledgement action, including for Command-W.
        false
    }
}

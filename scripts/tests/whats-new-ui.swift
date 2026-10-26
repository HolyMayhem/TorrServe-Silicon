import AppKit
import SwiftUI

@main
struct WhatsNewUIChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "TorrServeWhatsNewUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        json["enabled"] = false
        json["build"] = 42
        let resource = directory.appendingPathComponent("WhatsNew.json")
        try JSONSerialization.data(withJSONObject: json).write(to: resource)
        let parent = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 800, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { parent.close() }
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        func pump(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            } while Date() < deadline
        }
        func wait(_ message: String, until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(6)
            while !condition(), Date() < deadline { pump(0.05) }
            expect(condition(), message)
        }

        let preview = WhatsNewWindowController(defaults: defaults, resourceURL: resource, hadPreviousInstallation: true)
        preview.prepareLaunch(currentBuild: 42, appVersion: "2.9.0")
        expect(preview.manifest != nil, "Bundled announcement loads")
        expect(preview.preview(languageCode: "ru", relativeTo: parent), "Preview works with automatic presentation disabled")
        let window = preview.presentedWindow!
        pump(0.2)
        expect(window.isVisible, "Preview window is visible")
        expect(!window.styleMask.contains(.closable), "No standard close action")
        expect(!window.styleMask.contains(.resizable) && !window.styleMask.contains(.miniaturizable), "No resize or minimize controls")
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            expect(window.standardWindowButton(type)?.isHidden != false, "Standard window buttons are hidden")
        }
        expect(preview.preview(languageCode: "ru", relativeTo: parent) && preview.presentedWindow === window, "Repeated preview reuses one window")
        expect(!preview.windowShouldClose(window), "Window delegate refuses alternate close actions")
        window.performClose(nil)
        expect(window.isVisible, "The standard close command does not dismiss the announcement")

        if let snapshots = ProcessInfo.processInfo.environment["WHATS_NEW_SNAPSHOT_DIR"] {
            let target = URL(fileURLWithPath: snapshots, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                pump(0.3)
                let view = window.contentView!
                view.layoutSubtreeIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("whats-new-\(name).png"))
            }
        }
        preview.continuePresentation()
        expect(preview.presentedWindow == nil && !window.isVisible, "Continue dismisses the preview")

        // Same ID, next build: preview must not consume the real announcement.
        json["enabled"] = true
        json["build"] = 43
        try JSONSerialization.data(withJSONObject: json).write(to: resource)
        let automatic = WhatsNewWindowController(defaults: defaults, resourceURL: resource, hadPreviousInstallation: true)
        automatic.prepareLaunch(currentBuild: 43, appVersion: "2.9.1")
        automatic.observePresentationOpportunities(parent: parent) { "ru" }
        parent.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        wait("An eligible upgrade must present once the main window is active") { automatic.presentedWindow?.isVisible == true }
        automatic.continuePresentation()
        expect(automatic.presentedWindow == nil, "Continue acknowledges the automatic announcement")

        let reopened = WhatsNewWindowController(defaults: defaults, resourceURL: resource, hadPreviousInstallation: true)
        reopened.prepareLaunch(currentBuild: 43, appVersion: "2.9.1")
        reopened.observePresentationOpportunities(parent: parent) { "ru" }
        parent.makeKeyAndOrderFront(nil)
        pump(0.3)
        expect(reopened.presentedWindow == nil, "An acknowledged announcement does not reopen")
        expect(reopened.preview(languageCode: "en", relativeTo: parent), "Developer preview still works after acknowledgement")
        reopened.continuePresentation()
        print("Native What’s New UI: \(checks) checks passed")
    }
}

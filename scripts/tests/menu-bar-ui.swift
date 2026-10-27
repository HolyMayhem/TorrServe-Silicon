import AppKit
import SwiftUI

@main
struct MenuBarUIChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        func pump(_ seconds: TimeInterval = 0.25) {
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            } while Date() < deadline
        }
        func descendants(_ root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap { descendants($0) }
        }
        // Exercise real hit testing and button tracking at the approved layout's
        // control centers, without requiring Accessibility permission on CI.
        func click(x: CGFloat, y: CGFloat, in controller: MenuBarPopoverController) {
            let shell = controller.window.contentView!
            let point = shell.convert(NSPoint(x: x, y: y), to: nil)
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0)!
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.postEvent(up, atStart: false)
            controller.window.sendEvent(down)
            pump()
        }

        let screen = NSScreen.main!
        let parent = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 300,
            y: screen.visibleFrame.maxY - 40, width: 600, height: 30),
            styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let anchor = NSButton(frame: NSRect(x: 280, y: 4, width: 32, height: 22))
        parent.contentView!.addSubview(anchor)
        parent.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pump()
        defer { parent.close() }

        let model = MenuBarPopoverModel()
        model.language = .russian
        model.statusText = "Сервер запущен"
        model.statusKind = .running
        model.isRunning = true
        model.canStop = true
        model.activeTitle = "Дюна: Часть вторая (2024)"
        model.materialIsActive = true
        model.activeSizeText = "24,8 ГБ"
        model.bufferProgress = 0.68
        model.seeders = 42
        model.peers = 8
        model.speedText = "12,4 МБ/с"
        model.speedSamples = [2, 2.4, 2.1, 4, 3.7, 5, 4.7, 6, 5.2, 7, 8, 7.4, 9, 8.3, 10, 9.1, 11, 10.4, 9.8, 12, 11.4, 12.4]
        model.webUIAddress = "http://192.168.1.42:8090"
        // A real QR image is supplied by the app; keep a harmless fixture here.
        model.qrImage = NSImage(systemSymbolName: "qrcode", accessibilityDescription: nil)
        let controller = MenuBarPopoverController(model: model)
        var closed = 0
        controller.onClose = { closed += 1 }
        controller.show(relativeTo: anchor)
        pump()
        expect(controller.isShown && controller.window.isKeyWindow, "Popover opens and accepts keyboard focus")
        expect(abs(controller.contentView.fittingSize.width - 380) < 1, "Keep the approved content width")
        let root = controller.window.contentView!
        expect(!descendants(root).contains { $0 is NSVisualEffectView || String(describing: type(of: $0)).contains("GlassEffect") }, "The shell and sections contain no glass or vibrancy views")
        expect(controller.window.frame.minX >= screen.visibleFrame.minX && controller.window.frame.maxX <= screen.visibleFrame.maxX,
               "Popover stays horizontally on screen")
        let collapsed = controller.contentView.fittingSize.height
        func snapshot(_ name: String) throws {
            guard let directory = ProcessInfo.processInfo.environment["MENU_BAR_SNAPSHOT_DIR"] else { return }
            let target = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            root.layoutSubtreeIfNeeded()
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("menu-bar-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            controller.window.appearance = NSAppearance(named: appearance)
            pump()
            try snapshot(name)
        }
        var stopped = 0, started = 0, web = 0, shown = 0, downloaded = 0, quit = 0
        model.onStop = { stopped += 1 }
        model.onStart = { started += 1 }
        model.onOpenWeb = { web += 1 }
        model.onShowWindow = { shown += 1 }
        model.onDownload = { downloaded += 1 }
        model.onQuit = { quit += 1 }
        click(x: 68, y: 112, in: controller)
        click(x: 190, y: 112, in: controller)
        click(x: 310, y: 112, in: controller)
        click(x: 60, y: 20, in: controller)
        click(x: 345, y: 20, in: controller)
        expect(stopped == 1, "Stop click reaches the existing callback")
        expect(web == 1 && shown == 1, "Web UI and window clicks reach the existing callbacks")
        expect(downloaded == 1 && quit == 1, "Footer clicks reach the existing callbacks")

        let qrRowFromTop = root.bounds.height - 64
        click(x: 110, y: root.bounds.height - qrRowFromTop, in: controller)
        pump(0.35)
        expect(model.showsQRCode && controller.contentView.fittingSize.height > collapsed + 180,
               "QR disclosure expands the content")
        expect(controller.window.frame.minY >= screen.visibleFrame.minY,
               "Expanded content stays above the screen edge")
        try snapshot("qr-dark")
        click(x: 110, y: root.bounds.height - qrRowFromTop, in: controller)
        pump(0.35)
        expect(!model.showsQRCode && abs(controller.contentView.fittingSize.height - collapsed) < 1,
               "Collapsing QR restores the original height")

        model.canStop = false
        model.canStart = true
        model.isRunning = false
        model.activeTitle = nil
        model.bufferProgress = nil
        model.speedSamples = []
        model.statusText = "Сервер остановлен"
        model.statusKind = .stopped
        pump()
        click(x: 68, y: 112, in: controller)
        expect(started == 1, "Stopped state routes Start correctly")
        model.canStart = false
        pump()
        click(x: 68, y: 112, in: controller)
        expect(started == 1, "Unavailable actions stay disabled")
        try snapshot("stopped-dark")

        model.preferences.showsRecentMaterial = false
        model.preferences.showsSpeed = false
        model.preferences.showsQuickActions = false
        model.preferences.showsQRCode = false
        pump()
        expect(controller.contentView.fittingSize.height < 150, "Hidden blocks leave no empty cards or separator gaps")
        model.language = .english
        model.preferences = .defaults
        model.preferences.sectionOrder = [.qrCode, .quickActions, .speed, .recentMaterial]
        pump()
        expect(controller.contentView.fittingSize.width == 380, "English and reordered blocks retain the fixed width")
        try snapshot("english-dark")

        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: controller.window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        controller.window.sendEvent(escape)
        pump()
        expect(!controller.isShown && closed == 1, "Escape dismisses the menu and removes dismissal monitors")
        controller.performClose(nil)
        expect(closed == 1, "Repeated dismissal is harmless")
        controller.show(relativeTo: anchor)
        pump()
        expect(controller.isShown, "Menu reopens after Escape")
        controller.window.resignKey()
        pump()
        expect(!controller.isShown && closed == 2, "Losing focus dismisses the menu")
        print("Native menu bar UI: \(checks) checks passed")
    }
}

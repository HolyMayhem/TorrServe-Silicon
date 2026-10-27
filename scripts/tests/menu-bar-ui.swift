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
        func accessibilityTree(_ root: Any) -> [any NSAccessibilityProtocol] {
            guard let node = root as? any NSAccessibilityProtocol else { return [] }
            return [node] + (node.accessibilityChildren() ?? []).flatMap { accessibilityTree($0) }
        }
        func press(_ label: String, in controller: MenuBarPopoverController) {
            let buttons = accessibilityTree(controller.contentView).filter {
                $0.accessibilityRole() == .button && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == label
            }
            if buttons.count != 1 {
                for item in accessibilityTree(controller.contentView) {
                    print("AX: role=\(item.accessibilityRole()?.rawValue ?? "nil") label=\(item.accessibilityLabel() ?? "nil") title=\(item.accessibilityTitle() ?? "nil")")
                }
                fflush(stdout)
            }
            expect(buttons.count == 1, "Find one accessible button: \(label)")
            expect(buttons.first?.accessibilityPerformPress() == true, "Press \(label)")
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
        press(Texts(language: .russian).stop, in: controller)
        press("Web UI", in: controller)
        press(Texts(language: .russian).openWindow, in: controller)
        press(Texts(language: .russian).downloadArm, in: controller)
        press("Выйти", in: controller)
        expect(stopped == 1 && web == 1 && shown == 1 && downloaded == 1 && quit == 1, "Actions reach their existing callbacks")

        press(Texts(language: .russian).showQRCode, in: controller)
        expect(model.showsQRCode && controller.contentView.fittingSize.height > collapsed + 180,
               "QR disclosure expands the content")
        expect(controller.window.frame.minY >= screen.visibleFrame.minY,
               "Expanded content stays above the screen edge")
        try snapshot("qr-dark")
        press(Texts(language: .russian).hideQRCode, in: controller)
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
        press(Texts(language: .russian).start, in: controller)
        expect(started == 1, "Stopped state routes Start correctly")
        model.canStart = false
        pump()
        let startButton = accessibilityTree(controller.contentView).first {
            $0.accessibilityRole() == .button && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == Texts(language: .russian).start
        }
        expect(startButton?.isAccessibilityEnabled() == false, "Unavailable actions stay disabled")
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

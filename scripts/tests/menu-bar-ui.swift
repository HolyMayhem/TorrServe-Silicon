import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

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
        func activate(_ controller: MenuBarPopoverController) {
            guard !controller.window.isKeyWindow else { return }
            controller.synchronizeLayout()
            NSApp.activate(ignoringOtherApps: true)
            let deadline = Date().addingTimeInterval(5)
            repeat {
                controller.window.makeKeyAndOrderFront(nil)
                pump(0.05)
            } while !controller.window.isKeyWindow && Date() < deadline
            guard controller.isShown && controller.window.isKeyWindow else {
                fatalError("Native mouse checks require an active menu window")
            }
        }
        // Exercise real hit testing and button tracking at the approved layout's
        // control centers, without requiring Accessibility permission on CI.
        func click(x: CGFloat, y: CGFloat, in controller: MenuBarPopoverController) {
            activate(controller)
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
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(model.webUIAddress.utf8)
        let qrOutput = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let qr = CIContext().createCGImage(qrOutput, from: qrOutput.extent)!
        model.qrImage = NSImage(cgImage: qr, size: NSSize(width: 180, height: 180))
        let controller = MenuBarPopoverController(model: model)
        var closed = 0
        controller.onClose = { closed += 1 }
        controller.show(relativeTo: anchor)
        pump()
        activate(controller)
        expect(controller.isShown && controller.window.isKeyWindow, "Popover opens and accepts keyboard focus")
        expect(abs(controller.naturalContentSize.width - 380) < 1, "Keep the approved content width")
        let root = controller.window.contentView!
        let surfaces = descendants(root).compactMap { $0 as? NSVisualEffectView }
        expect(surfaces.count == 1 && surfaces[0].material == .popover
               && surfaces[0].blendingMode == .behindWindow && surfaces[0].maskImage != nil,
               "A single system blur surface covers the menu and follows its rounded arrow shape")
        expect(controller.window.frame.minX >= screen.visibleFrame.minX && controller.window.frame.maxX <= screen.visibleFrame.maxX,
               "Popover stays horizontally on screen")
        let collapsed = controller.naturalContentSize.height
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
        expect(model.showsQRCode && controller.naturalContentSize.height > collapsed + 180,
               "QR disclosure expands the content")
        expect(controller.window.frame.minY >= screen.visibleFrame.minY,
               "Expanded content stays above the screen edge")
        try snapshot("qr-dark")
        click(x: 110, y: root.bounds.height - qrRowFromTop, in: controller)
        pump(0.35)
        expect(!model.showsQRCode && abs(controller.naturalContentSize.height - collapsed) < 1,
               "Collapsing QR restores the original height")

        model.canStop = false
        model.canStart = true
        model.isRunning = false
        model.activeTitle = nil
        model.materialIsActive = false
        model.speedText = "0 МБ/с"
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
        expect(controller.naturalContentSize.height < 150, "Hidden blocks leave no empty cards or separator gaps")
        model.language = .english
        model.preferences = .defaults
        model.preferences.sectionOrder = [.qrCode, .quickActions, .speed, .recentMaterial]
        pump()
        expect(controller.naturalContentSize.width == 380, "English and reordered blocks retain the fixed width")
        try snapshot("english-dark")

        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: controller.window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        activate(controller)
        let closesBeforeEscape = closed
        controller.window.sendEvent(escape)
        pump()
        expect(!controller.isShown && closed == closesBeforeEscape + 1, "Escape dismisses the menu and removes dismissal monitors")
        controller.performClose(nil)
        expect(closed == closesBeforeEscape + 1, "Repeated dismissal is harmless")
        controller.show(relativeTo: anchor)
        pump()
        activate(controller)
        expect(controller.isShown, "Menu reopens after Escape")
        let closesBeforeResign = closed
        controller.window.resignKey()
        pump()
        expect(!controller.isShown && closed == closesBeforeResign + 1, "Losing focus dismisses the menu")
        // Each extra works independently of the original quick-actions group.
        var onlyExtras = MenuBarPreferences.defaults
        onlyExtras.showsRecentMaterial = false
        onlyExtras.showsSpeed = false
        onlyExtras.showsQuickActions = false
        onlyExtras.showsQRCode = false
        model.language = .russian
        model.isRunning = true
        model.canStop = true
        model.isRestarting = false
        var restarts = 0, settings = 0, updates = 0, library = 0
        model.onRestart = { restarts += 1 }
        model.onShowSettings = { settings += 1 }
        model.onShowUpdates = { updates += 1 }
        model.onShowLibrary = { library += 1 }
        for option in [MenuBarExtraOption.restart, .settings, .activeTorrents, .updateStatus] {
            var selected = onlyExtras
            selected[keyPath: option.keyPath] = true
            model.preferences = selected
            controller.show(relativeTo: anchor)
            pump()
            expect(controller.naturalContentSize.height < 220, "A single extra does not bring hidden blocks back")
            click(x: 100, y: 60, in: controller)
            controller.performClose(nil)
        }
        expect(restarts == 1 && settings == 1 && updates == 1 && library == 1,
               "Restart, settings, updates, and library actions route independently")
        var copyOnly = onlyExtras
        copyOnly.showsCopyAddress = true
        model.preferences = copyOnly
        controller.show(relativeTo: anchor)
        pump()
        click(x: 354, y: 60, in: controller)
        expect(NSPasteboard.general.string(forType: .string) == model.webUIAddress, "Copy writes the full connection URL")
        controller.performClose(nil)
        var restartOnly = onlyExtras
        restartOnly.showsRestart = true
        model.preferences = restartOnly
        model.isRestarting = true
        controller.show(relativeTo: anchor)
        pump()
        click(x: 100, y: 60, in: controller)
        expect(restarts == 1, "Prevent duplicate restarts while busy")
        controller.performClose(nil)

        var all = MenuBarPreferences.defaults
        for option in MenuBarExtraOption.allCases { all[keyPath: option.keyPath] = true }
        model.preferences = all
        model.isRestarting = false
        model.statusText = "Сервер запущен"
        model.statusKind = .running
        model.activeTitle = "Дюна: Часть вторая (2024)"
        model.materialIsActive = true
        model.bufferProgress = 0.68
        model.speedText = "12,4 МБ/с"
        model.speedSamples = [2, 2.4, 2.1, 4, 3.7, 5, 4.7, 6, 5.2, 7, 8, 7.4, 9, 8.3, 10, 9.1, 11, 10.4, 9.8, 12, 11.4, 12.4]
        model.installedVersion = "MatriX.147"
        model.availableVersion = "MatriX.147.1"
        model.activeTorrentCount = 3
        model.cacheSnapshot = MenuBarCacheSnapshot(used: 640 * 1024 * 1024, capacity: 2 * 1024 * 1024 * 1024)

        func exportView<V: View>(_ view: V, name: String, appearance: NSAppearance.Name) throws -> NSHostingView<V> {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let preview = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            preview.isReleasedWhenClosed = false
            preview.contentView = host
            preview.appearance = host.appearance
            preview.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            host.layoutSubtreeIfNeeded()
            pump()
            if let directory = ProcessInfo.processInfo.environment["MENU_BAR_SNAPSHOT_DIR"] {
                let target = URL(fileURLWithPath: directory, isDirectory: true)
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("menu-bar-\(name).png"))
            }
            preview.orderOut(nil)
            return host
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let full = try exportView(MenuBarPopoverView(model: model), name: "all-enabled-\(name)", appearance: appearance)
            expect(full.bounds.height > collapsed + 200, "Export every enabled block, including below the viewport")
        }
        let originalParentFrame = parent.frame
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX, y: screen.visibleFrame.minY + 280))
        NSApp.activate(ignoringOtherApps: true)
        controller.show(relativeTo: anchor)
        pump()
        activate(controller)
        expect(controller.window.isKeyWindow, "The fitted menu is active before testing native mouse clicks")
        expect(controller.window.frame.minY >= screen.visibleFrame.minY, "All extras fit the screen without scrolling")
        expect(controller.contentView.convert(controller.contentView.bounds, to: root).height < controller.naturalContentSize.height,
               "Limited space fits an oversized menu instead of clipping its bottom")
        expect(!descendants(root).contains { $0 is NSScrollView }, "The menu has no scrolling container")
        let visibleContent = controller.contentView.convert(controller.contentView.bounds, to: root)
        expect(root.bounds.insetBy(dx: 0.5, dy: 0.5).contains(visibleContent),
               "The whole menu, including its footer, fits inside the visible panel")
        let originalBounds = controller.contentView.bounds
        let originalFrame = controller.window.frame
        for delta: Int32 in [-240, 240] {
            let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: delta, wheel2: 0, wheel3: 0)!
            controller.contentView.scrollWheel(with: NSEvent(cgEvent: wheel)!)
            pump(0.1)
        }
        expect(controller.contentView.bounds == originalBounds && controller.window.frame == originalFrame,
               "Precise upward and downward scroll events must not move the menu")
        let quitsBeforeFitClick = quit
        let fittedScale = controller.contentView.bounds.width / controller.naturalContentSize.width
        let footerY = controller.contentView.isFlipped ? controller.contentView.bounds.maxY - 20 * fittedScale : 20 * fittedScale
        let quitPoint = controller.contentView.convert(NSPoint(x: 355 * fittedScale, y: footerY), to: root)
        try snapshot("fitted-menu")
        click(x: quitPoint.x, y: quitPoint.y, in: controller)
        expect(quit == quitsBeforeFitClick + 1, "The fitted menu footer keeps correct native hit testing")
        controller.performClose(nil)
        parent.setFrame(originalParentFrame, display: false)

        // The existing native editor must wrap ten draggable chips and move
        // items between rows without changing their independent visibility.
        var editedOrder = all.sectionOrder
        let editor = try exportView(MenuBarEditorPreview(preferences: all, language: .russian) {
            editedOrder = $0
        }, name: "editor-all-enabled", appearance: .aqua)
        guard let orderControl = descendants(editor).first(where: {
            String(describing: type(of: $0)) == "MenuBarSectionOrderNSView"
        }) else { fatalError("Native order editor missing") }
        let chips = orderControl.subviews
        expect(chips.count == 10, "All old and new sections can be reordered")
        expect(chips.allSatisfy { $0.frame.maxX <= orderControl.bounds.maxX + 1 && $0.frame.minX >= 0 },
               "Order chips wrap without horizontal clipping")
        expect(Set(chips.map { Int($0.frame.minY) }).count > 1, "Editor uses several rows")
        let first = chips.first { $0.accessibilityLabel() == MenuBarPopoverSection.serverVersion.title(language: .russian) }!
        let last = chips.first { $0.accessibilityLabel() == MenuBarPopoverSection.settings.title(language: .russian) }!
        func dragEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: orderControl.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: orderControl.window?.windowNumber ?? 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let source = NSPoint(x: last.frame.midX, y: last.frame.midY)
        let destination = NSPoint(x: first.frame.midX, y: first.frame.midY)
        orderControl.mouseDown(with: dragEvent(.leftMouseDown, at: source))
        orderControl.mouseDragged(with: dragEvent(.leftMouseDragged, at: destination))
        orderControl.mouseUp(with: dragEvent(.leftMouseUp, at: destination))
        pump()
        expect(editedOrder.first == .settings && editedOrder.count == 10, "Drag a new block across editor rows")
        print("Native menu bar UI: \(checks) checks passed")
    }
}

private struct MenuBarEditorPreview: View {
    let preferences: MenuBarPreferences
    let language: AppLanguage
    let onChange: ([MenuBarPopoverSection]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Редактор меню").font(.system(size: 22, weight: .semibold))
            Text("Дополнительные элементы").font(.headline)
            VStack(spacing: 10) {
                ForEach(MenuBarExtraOption.allCases) { option in
                    HStack {
                        Text(option.title(language: language))
                        Spacer()
                        Toggle("", isOn: .constant(preferences[keyPath: option.keyPath]))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    if option != MenuBarExtraOption.allCases.last { Divider() }
                }
            }
            Text("Порядок элементов").font(.headline)
            Text("Перетащите любой блок на нужное место. Отключённые элементы показаны бледнее.")
                .font(.caption).foregroundStyle(.secondary)
            MenuBarSectionOrderView(sections: preferences.sectionOrder, preferences: preferences,
                                    language: language, onChange: onChange)
        }
        .padding(24)
        .frame(width: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

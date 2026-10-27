import AppKit
import Combine
import SwiftUI

/// Own the popover's shape and its system blur surface, including the arrow.
@MainActor
final class MenuBarPopoverController: NSObject, NSWindowDelegate {
    private let panel = MenuBarPanel()
    private let shell = MenuBarPopoverShell()
    private let model: MenuBarPopoverModel
    private let measurementView: NSHostingView<MenuBarPopoverView>
    private let hostingView: NSHostingView<MenuBarPopoverPresentation>
    private weak var anchor: NSView?
    private var modelChanges: AnyCancellable?
    private var isClosing = false
    var onClose: (() -> Void)?

    var isShown: Bool { panel.isVisible }
    var window: NSWindow { panel }
    var contentView: NSView { hostingView }
    var naturalContentSize: NSSize { measurementView.fittingSize }

    init(model: MenuBarPopoverModel) {
        self.model = model
        measurementView = NSHostingView(rootView: MenuBarPopoverView(model: model))
        hostingView = NSHostingView(rootView: MenuBarPopoverPresentation(model: model, size: .zero, scale: 1))
        super.init()
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.onEscape = { [weak self] in self?.performClose(nil) }
        panel.contentView = shell

        shell.addSubview(hostingView)
        modelChanges = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isShown else { return }
                self.synchronizeLayout()
            }
        }
    }

    func show(relativeTo view: NSView) {
        anchor = view
        synchronizeLayout()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hostingView)
    }

    func performClose(_ sender: Any?) {
        guard isShown, !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        panel.orderOut(sender)
        onClose?()
    }

    func synchronizeLayout() {
        guard let anchor, let anchorWindow = anchor.window,
              let screen = anchorWindow.screen ?? NSScreen.main else { return }

        measurementView.layoutSubtreeIfNeeded()
        let ideal = naturalContentSize
        guard ideal.width > 0, ideal.height > 0 else { return }
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let available = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        let top = min(anchorRect.minY, available.maxY)
        // Keep all entries reachable without a scrolling or bouncing container.
        // Normal menus stay at their natural size; oversized menus fit the screen.
        let availableContentHeight = max(top - available.minY - MenuBarPopoverShell.arrowHeight - 2, 1)
        let scale = min(1, availableContentHeight / ideal.height)
        let contentSize = NSSize(width: ideal.width * scale, height: ideal.height * scale)
        let width = contentSize.width + 2
        let height = contentSize.height + 2 + MenuBarPopoverShell.arrowHeight
        let left = min(max(anchorRect.midX - width / 2, available.minX), available.maxX - width)
        let frame = NSRect(x: left, y: top - height, width: width, height: height)

        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        shell.frame = NSRect(origin: .zero, size: frame.size)
        shell.arrowX = min(max(anchorRect.midX - left, 20), width - 20)
        shell.updateSurfaceMask()
        hostingView.rootView = MenuBarPopoverPresentation(model: model, size: ideal, scale: scale)
        hostingView.frame = NSRect(origin: NSPoint(x: 1, y: 1), size: contentSize)
        shell.needsDisplay = true
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        performClose(nil)
    }
}

private struct MenuBarPopoverPresentation: View {
    let model: MenuBarPopoverModel
    let size: NSSize
    let scale: CGFloat

    var body: some View {
        MenuBarPopoverView(model: model)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
    }
}

private final class MenuBarPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class MenuBarPopoverShell: NSVisualEffectView {
    static let arrowHeight: CGFloat = 8
    var arrowX: CGFloat = 190
    private var maskedSize = NSSize.zero
    private var maskedArrowX: CGFloat = .nan

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    private func configureSurface() {
        material = .popover
        blendingMode = .behindWindow
        state = .active
    }

    func updateSurfaceMask() {
        guard bounds.width > 0, bounds.height > 0,
              bounds.size != maskedSize || arrowX != maskedArrowX else { return }
        maskedSize = bounds.size
        maskedArrowX = arrowX
        let path = surfacePath
        maskImage = NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.white.setFill()
            path.fill()
            return true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let path = surfacePath
        path.lineWidth = 1
        path.stroke()
    }

    private var surfacePath: NSBezierPath {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let top = rect.maxY - Self.arrowHeight
        let radius: CGFloat = 12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
                       radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: top - radius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: top - radius),
                       radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: arrowX + 8, y: top))
        path.line(to: NSPoint(x: arrowX, y: rect.maxY))
        path.line(to: NSPoint(x: arrowX - 8, y: top))
        path.line(to: NSPoint(x: rect.minX + radius, y: top))
        path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: top - radius),
                       radius: radius, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
                       radius: radius, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }
}

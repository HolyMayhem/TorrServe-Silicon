import AppKit
import Combine
import SwiftUI

/// Own the small popover shell so macOS 26 cannot add Liquid Glass behind the
/// otherwise opaque content. Uses public AppKit drawing and window APIs only.
@MainActor
final class MenuBarPopoverController: NSObject, NSWindowDelegate {
    private let panel = MenuBarPanel()
    private let shell = MenuBarPopoverShell()
    private let scrollView = NSScrollView()
    private let hostingView: NSHostingView<MenuBarPopoverView>
    private weak var anchor: NSView?
    private var modelChanges: AnyCancellable?
    var onClose: (() -> Void)?

    var isShown: Bool { panel.isVisible }
    var window: NSWindow { panel }
    var contentView: NSView { hostingView }

    init(model: MenuBarPopoverModel) {
        hostingView = NSHostingView(rootView: MenuBarPopoverView(model: model))
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

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 11
        scrollView.layer?.masksToBounds = true
        scrollView.documentView = hostingView
        shell.addSubview(scrollView)
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
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func performClose(_ sender: Any?) {
        guard isShown else { return }
        panel.orderOut(sender)
        onClose?()
    }

    func synchronizeLayout() {
        guard let anchor, let anchorWindow = anchor.window,
              let screen = anchorWindow.screen ?? NSScreen.main else { return }

        hostingView.layoutSubtreeIfNeeded()
        let ideal = hostingView.fittingSize
        guard ideal.width > 0, ideal.height > 0 else { return }
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let available = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        let top = min(anchorRect.minY, available.maxY)
        let width = ideal.width + 2
        let height = min(ideal.height + 2 + MenuBarPopoverShell.arrowHeight, top - available.minY)
        let left = min(max(anchorRect.midX - width / 2, available.minX), available.maxX - width)
        let frame = NSRect(x: left, y: top - height, width: width, height: height)

        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        shell.frame = NSRect(origin: .zero, size: frame.size)
        shell.arrowX = min(max(anchorRect.midX - left, 20), width - 20)
        scrollView.frame = NSRect(x: 1, y: 1, width: ideal.width,
                                  height: height - MenuBarPopoverShell.arrowHeight - 2)
        hostingView.frame = NSRect(origin: .zero, size: ideal)
        shell.needsDisplay = true
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        performClose(nil)
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

private final class MenuBarPopoverShell: NSView {
    static let arrowHeight: CGFloat = 8
    var arrowX: CGFloat = 190
    override var allowsVibrancy: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
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
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

import AppKit
import QuartzCore
import SwiftUI

struct MetadataProviderOrderView: View {
    let providers: [MetadataProvider]
    let language: AppLanguage
    let onChange: ([MetadataProvider]) -> Void

    var body: some View {
        MetadataProviderOrderControl(
            providers: providers,
            helpText: language == .russian
                ? "Перетащите источник влево или вправо, чтобы изменить приоритет"
                : "Drag a source left or right to change priority",
            onChange: onChange
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(language == .russian
            ? "Порядок источников метаданных"
            : "Metadata provider order")
    }
}

enum MetadataProviderOrdering {
    static func moving(
        _ providers: [MetadataProvider],
        provider: MetadataProvider,
        to destinationIndex: Int
    ) -> [MetadataProvider] {
        guard let sourceIndex = providers.firstIndex(of: provider) else {
            return MetadataProviderSettings.normalizedOrder(providers)
        }

        var updated = providers
        updated.remove(at: sourceIndex)
        let insertionIndex = min(max(destinationIndex, 0), updated.endIndex)
        updated.insert(provider, at: insertionIndex)
        return MetadataProviderSettings.normalizedOrder(updated)
    }
}

private struct MetadataProviderOrderControl: NSViewRepresentable {
    let providers: [MetadataProvider]
    let helpText: String
    let onChange: ([MetadataProvider]) -> Void

    func makeNSView(context: Context) -> MetadataProviderOrderNSView {
        MetadataProviderOrderNSView(
            providers: providers,
            helpText: helpText,
            onChange: onChange
        )
    }

    func updateNSView(_ nsView: MetadataProviderOrderNSView, context: Context) {
        nsView.update(
            providers: providers,
            helpText: helpText,
            onChange: onChange
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MetadataProviderOrderNSView,
        context: Context
    ) -> CGSize? {
        let intrinsicSize = nsView.intrinsicContentSize
        return CGSize(
            width: proposal.width ?? intrinsicSize.width,
            height: intrinsicSize.height
        )
    }
}

private final class MetadataProviderOrderNSView: NSView {
    private let chipHeight: CGFloat = 29
    private let controlHeight: CGFloat = 37
    private let arrowWidth: CGFloat = 18
    private let itemSpacing: CGFloat = 7
    private let dragThreshold: CGFloat = 2
    private let reorderAnimationDuration: TimeInterval = 0.18
    private let chipVerticalOffset: CGFloat = -4

    private var providers: [MetadataProvider]
    private var workingProviders: [MetadataProvider]
    private var onChange: ([MetadataProvider]) -> Void
    private var chipViews: [MetadataProvider: MetadataProviderChipView] = [:]
    private var arrowViews: [NSTextField] = []
    private var draggedProvider: MetadataProvider?
    private var mouseDownPoint: NSPoint?
    private var dragGrabOffsetX: CGFloat = 0
    private var hasDragged = false

    init(
        providers: [MetadataProvider],
        helpText: String,
        onChange: @escaping ([MetadataProvider]) -> Void
    ) {
        let normalized = MetadataProviderSettings.normalizedOrder(providers)
        self.providers = normalized
        workingProviders = normalized
        self.onChange = onChange
        super.init(frame: .zero)

        wantsLayer = true
        toolTip = helpText
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Metadata provider order")
        rebuildSubviews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // The application window can be dragged by its background. This control must
    // opt out so pointer movement is delivered as a drag gesture instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth(for: workingProviders), height: controlHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        chipViews.values.contains(where: { $0.frame.contains(point) }) ? self : nil
    }

    override func layout() {
        super.layout()
        guard !hasDragged else { return }
        positionSubviews(animated: false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let provider = workingProviders.first(where: {
            chipViews[$0]?.frame.contains(point) == true
        }), let chipView = chipViews[provider] else {
            return
        }

        window?.makeFirstResponder(self)
        draggedProvider = provider
        mouseDownPoint = point
        dragGrabOffsetX = point.x - chipView.frame.minX
        hasDragged = false
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draggedProvider,
              let mouseDownPoint,
              let draggedView = chipViews[draggedProvider] else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if !hasDragged {
            let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            guard distance >= dragThreshold else { return }
            hasDragged = true
            draggedView.setDragging(true)
            addSubview(draggedView, positioned: .above, relativeTo: nil)
            NSCursor.closedHand.set()
        }

        var draggedFrame = draggedView.frame
        draggedFrame.origin.x = min(
            max(point.x - dragGrabOffsetX, 0),
            max(bounds.width - draggedFrame.width, 0)
        )
        draggedFrame.origin.y = targetY + chipVerticalOffset
        draggedView.frame = draggedFrame

        let targetFrames = chipFrames(for: workingProviders)
        guard let destinationIndex = targetFrames.indices.min(by: {
            abs(targetFrames[$0].midX - draggedFrame.midX)
                < abs(targetFrames[$1].midX - draggedFrame.midX)
        }),
        workingProviders.firstIndex(of: draggedProvider) != destinationIndex else {
            return
        }

        workingProviders = MetadataProviderOrdering.moving(
            workingProviders,
            provider: draggedProvider,
            to: destinationIndex
        )
        positionSubviews(animated: true, excluding: draggedProvider)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard let draggedProvider else { return }

        let changedOrder = hasDragged && workingProviders != providers
        let updatedOrder = workingProviders
        let draggedView = chipViews[draggedProvider]

        self.draggedProvider = nil
        mouseDownPoint = nil
        hasDragged = false
        NSCursor.arrow.set()
        window?.invalidateCursorRects(for: self)

        positionSubviews(animated: true)
        draggedView?.setDragging(false)

        if changedOrder {
            providers = updatedOrder
            onChange(updatedOrder)
        } else {
            workingProviders = providers
            positionSubviews(animated: true)
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = hasDragged ? .closedHand : .openHand
        for chipView in chipViews.values {
            addCursorRect(chipView.frame, cursor: cursor)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        chipViews.values.forEach { $0.needsDisplay = true }
    }

    func update(
        providers: [MetadataProvider],
        helpText: String,
        onChange: @escaping ([MetadataProvider]) -> Void
    ) {
        let normalized = MetadataProviderSettings.normalizedOrder(providers)
        self.onChange = onChange
        toolTip = helpText

        guard draggedProvider == nil else { return }
        guard self.providers != normalized || workingProviders != normalized else { return }

        self.providers = normalized
        workingProviders = normalized
        rebuildSubviews()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var targetY: CGFloat {
        (bounds.height - chipHeight) / 2
    }

    private func rebuildSubviews() {
        for provider in workingProviders where chipViews[provider] == nil {
            let chipView = MetadataProviderChipView(provider: provider)
            chipViews[provider] = chipView
            addSubview(chipView)
        }

        let requiredArrowCount = max(workingProviders.count - 1, 0)
        while arrowViews.count < requiredArrowCount {
            let arrowView = NSTextField(labelWithString: "→")
            arrowView.font = .systemFont(ofSize: 12, weight: .semibold)
            arrowView.textColor = .tertiaryLabelColor
            arrowView.alignment = .center
            arrowViews.append(arrowView)
            addSubview(arrowView)
        }
        while arrowViews.count > requiredArrowCount {
            arrowViews.removeLast().removeFromSuperview()
        }

        positionSubviews(animated: false)
    }

    private func positionSubviews(
        animated: Bool,
        excluding excludedProvider: MetadataProvider? = nil
    ) {
        let frames = chipFrames(for: workingProviders)
        let applyFrames: (_ useAnimator: Bool) -> Void = { useAnimator in
            for (index, provider) in self.workingProviders.enumerated() {
                if provider != excludedProvider {
                    if useAnimator {
                        self.chipViews[provider]?.animator().frame = frames[index]
                    } else {
                        self.chipViews[provider]?.frame = frames[index]
                    }
                }

                guard index < self.arrowViews.count else { continue }
                let leftFrame = frames[index]
                let rightFrame = frames[index + 1]
                let expectedCenter = (leftFrame.maxX + rightFrame.minX) / 2
                let arrowFrame = NSRect(
                    x: expectedCenter - self.arrowWidth / 2,
                    y: self.targetY + 2,
                    width: self.arrowWidth,
                    height: self.chipHeight
                )
                if useAnimator {
                    self.arrowViews[index].animator().frame = arrowFrame
                } else {
                    self.arrowViews[index].frame = arrowFrame
                }
            }
        }

        guard animated, window != nil else {
            applyFrames(false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reorderAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyFrames(true)
        }
    }

    private func chipFrames(for values: [MetadataProvider]) -> [NSRect] {
        let totalWidth = totalWidth(for: values)
        var x = max((bounds.width - totalWidth) / 2, 0)

        return values.enumerated().map { index, provider in
            let width = chipViews[provider]?.intrinsicContentSize.width
                ?? MetadataProviderChipView.width(for: provider)
            let frame = NSRect(
                x: x,
                y: targetY + chipVerticalOffset,
                width: width,
                height: chipHeight
            )
            x += width
            if index < values.count - 1 {
                x += itemSpacing + arrowWidth + itemSpacing
            }
            return frame
        }
    }

    private func totalWidth(for values: [MetadataProvider]) -> CGFloat {
        let chipsWidth = values.reduce(CGFloat.zero) { result, provider in
            result + (chipViews[provider]?.intrinsicContentSize.width
                ?? MetadataProviderChipView.width(for: provider))
        }
        let separatorsWidth = CGFloat(max(values.count - 1, 0))
            * (itemSpacing + arrowWidth + itemSpacing)
        return chipsWidth + separatorsWidth
    }
}

private final class MetadataProviderChipView: NSView {
    private let backgroundView: NSView
    private let label: NSTextField
    private var isDragging = false

    init(provider: MetadataProvider) {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = 14.5
            glassView.tintColor = .secondaryLabelColor.withAlphaComponent(0.06)
            backgroundView = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .popover
            effectView.blendingMode = .withinWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 14.5
            effectView.layer?.masksToBounds = true
            backgroundView = effectView
        }
        label = NSTextField(labelWithString: provider.displayName)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(provider.displayName)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 22, height: 29)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = bounds.height / 2
        layer?.borderWidth = isDragging ? 1.5 : 1
        layer?.borderColor = (isDragging
            ? NSColor.controlAccentColor
            : NSColor.separatorColor.withAlphaComponent(0.45)
        ).cgColor

        if #available(macOS 26.0, *), let glassView = backgroundView as? NSGlassEffectView {
            glassView.tintColor = isDragging
                ? NSColor.controlAccentColor.withAlphaComponent(0.20)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.06)
        } else if let effectView = backgroundView as? NSVisualEffectView {
            effectView.layer?.backgroundColor = (isDragging
                ? NSColor.controlAccentColor.withAlphaComponent(0.16)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.04)
            ).cgColor
        }
    }

    func setDragging(_ dragging: Bool) {
        guard isDragging != dragging else { return }
        isDragging = dragging

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -3)
        layer?.shadowRadius = dragging ? 7 : 0
        layer?.shadowOpacity = dragging ? 0.30 : 0
        layer?.setAffineTransform(dragging
            ? CGAffineTransform(scaleX: 1.04, y: 1.04)
            : .identity)
        CATransaction.commit()
        needsDisplay = true
    }

    static func width(for provider: MetadataProvider) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        return ceil((provider.displayName as NSString).size(withAttributes: attributes).width) + 22
    }
}

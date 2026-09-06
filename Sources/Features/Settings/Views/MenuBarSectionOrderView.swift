import AppKit
import QuartzCore
import SwiftUI

struct MenuBarSectionOrderView: View {
    let sections: [MenuBarPopoverSection]
    let preferences: MenuBarPreferences
    let language: AppLanguage
    let onChange: ([MenuBarPopoverSection]) -> Void

    var body: some View {
        MenuBarSectionOrderControl(
            sections: sections,
            preferences: preferences,
            language: language,
            helpText: language == .russian
                ? "Перетащите элемент влево или вправо, чтобы изменить порядок"
                : "Drag an item left or right to change its order",
            onChange: onChange
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(language == .russian
            ? "Порядок элементов меню-бара"
            : "Menu bar item order")
    }
}

enum MenuBarSectionOrdering {
    static func moving(
        _ sections: [MenuBarPopoverSection],
        section: MenuBarPopoverSection,
        to destinationIndex: Int
    ) -> [MenuBarPopoverSection] {
        guard let sourceIndex = sections.firstIndex(of: section) else {
            return MenuBarPreferences.normalizedOrder(sections)
        }

        var result = sections
        result.remove(at: sourceIndex)
        let insertionIndex = min(max(destinationIndex, 0), result.endIndex)
        result.insert(section, at: insertionIndex)
        return MenuBarPreferences.normalizedOrder(result)
    }
}

private struct MenuBarSectionOrderControl: NSViewRepresentable {
    let sections: [MenuBarPopoverSection]
    let preferences: MenuBarPreferences
    let language: AppLanguage
    let helpText: String
    let onChange: ([MenuBarPopoverSection]) -> Void

    func makeNSView(context: Context) -> MenuBarSectionOrderNSView {
        MenuBarSectionOrderNSView(
            sections: sections,
            preferences: preferences,
            language: language,
            helpText: helpText,
            onChange: onChange
        )
    }

    func updateNSView(_ nsView: MenuBarSectionOrderNSView, context: Context) {
        nsView.update(
            sections: sections,
            preferences: preferences,
            language: language,
            helpText: helpText,
            onChange: onChange
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MenuBarSectionOrderNSView,
        context: Context
    ) -> CGSize? {
        let intrinsicSize = nsView.intrinsicContentSize
        return CGSize(
            width: proposal.width ?? intrinsicSize.width,
            height: intrinsicSize.height
        )
    }
}

private final class MenuBarSectionOrderNSView: NSView {
    private let chipHeight: CGFloat = 29
    private let controlHeight: CGFloat = 37
    private let itemSpacing: CGFloat = 7
    private let dragThreshold: CGFloat = 2
    private let reorderAnimationDuration: TimeInterval = 0.18
    private let chipVerticalOffset: CGFloat = -4

    private var sections: [MenuBarPopoverSection]
    private var workingSections: [MenuBarPopoverSection]
    private var preferences: MenuBarPreferences
    private var language: AppLanguage
    private var onChange: ([MenuBarPopoverSection]) -> Void
    private var chipViews: [MenuBarPopoverSection: MenuBarSectionChipView] = [:]
    private var draggedSection: MenuBarPopoverSection?
    private var mouseDownPoint: NSPoint?
    private var dragGrabOffsetX: CGFloat = 0
    private var hasDragged = false

    init(
        sections: [MenuBarPopoverSection],
        preferences: MenuBarPreferences,
        language: AppLanguage,
        helpText: String,
        onChange: @escaping ([MenuBarPopoverSection]) -> Void
    ) {
        let normalized = MenuBarPreferences.normalizedOrder(sections)
        self.sections = normalized
        workingSections = normalized
        self.preferences = preferences
        self.language = language
        self.onChange = onChange
        super.init(frame: .zero)

        wantsLayer = true
        toolTip = helpText
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibilityLabel()
        rebuildSubviews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // The settings window can be dragged by its background. Keep mouse drags
    // inside this control so reordering works reliably.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth(for: workingSections), height: controlHeight)
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
        guard let section = workingSections.first(where: {
            chipViews[$0]?.frame.contains(point) == true
        }), let chipView = chipViews[section] else {
            return
        }

        window?.makeFirstResponder(self)
        draggedSection = section
        mouseDownPoint = point
        dragGrabOffsetX = point.x - chipView.frame.minX
        hasDragged = false
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draggedSection,
              let mouseDownPoint,
              let draggedView = chipViews[draggedSection] else {
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

        let targetFrames = chipFrames(for: workingSections)
        guard let destinationIndex = targetFrames.indices.min(by: {
            abs(targetFrames[$0].midX - draggedFrame.midX)
                < abs(targetFrames[$1].midX - draggedFrame.midX)
        }),
        workingSections.firstIndex(of: draggedSection) != destinationIndex else {
            return
        }

        workingSections = MenuBarSectionOrdering.moving(
            workingSections,
            section: draggedSection,
            to: destinationIndex
        )
        positionSubviews(animated: true, excluding: draggedSection)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard let draggedSection else { return }

        let changedOrder = hasDragged && workingSections != sections
        let updatedOrder = workingSections
        let draggedView = chipViews[draggedSection]

        self.draggedSection = nil
        mouseDownPoint = nil
        hasDragged = false
        NSCursor.arrow.set()
        window?.invalidateCursorRects(for: self)

        positionSubviews(animated: true)
        draggedView?.setDragging(false)

        if changedOrder {
            sections = updatedOrder
            onChange(updatedOrder)
        } else {
            workingSections = sections
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
        sections: [MenuBarPopoverSection],
        preferences: MenuBarPreferences,
        language: AppLanguage,
        helpText: String,
        onChange: @escaping ([MenuBarPopoverSection]) -> Void
    ) {
        let normalized = MenuBarPreferences.normalizedOrder(sections)
        self.preferences = preferences
        self.language = language
        self.onChange = onChange
        toolTip = helpText
        updateAccessibilityLabel()

        for (section, chipView) in chipViews {
            chipView.update(
                title: section.title(language: language),
                isVisible: preferences.isVisible(section)
            )
        }

        guard draggedSection == nil else { return }
        guard self.sections != normalized || workingSections != normalized else {
            invalidateIntrinsicContentSize()
            needsLayout = true
            return
        }

        self.sections = normalized
        workingSections = normalized
        rebuildSubviews()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var targetY: CGFloat {
        (bounds.height - chipHeight) / 2
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel(language == .russian
            ? "Порядок элементов меню-бара"
            : "Menu bar item order")
    }

    private func rebuildSubviews() {
        for section in workingSections where chipViews[section] == nil {
            let chipView = MenuBarSectionChipView(
                section: section,
                title: section.title(language: language),
                isVisible: preferences.isVisible(section)
            )
            chipViews[section] = chipView
            addSubview(chipView)
        }

        positionSubviews(animated: false)
    }

    private func positionSubviews(
        animated: Bool,
        excluding excludedSection: MenuBarPopoverSection? = nil
    ) {
        let frames = chipFrames(for: workingSections)
        let applyFrames: (_ useAnimator: Bool) -> Void = { useAnimator in
            for (index, section) in self.workingSections.enumerated()
                where section != excludedSection {
                if useAnimator {
                    self.chipViews[section]?.animator().frame = frames[index]
                } else {
                    self.chipViews[section]?.frame = frames[index]
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

    private func chipFrames(for values: [MenuBarPopoverSection]) -> [NSRect] {
        var x: CGFloat = 0
        return values.enumerated().map { index, section in
            let width = chipViews[section]?.intrinsicContentSize.width
                ?? MenuBarSectionChipView.width(
                    for: section.title(language: language)
                )
            let frame = NSRect(
                x: x,
                y: targetY + chipVerticalOffset,
                width: width,
                height: chipHeight
            )
            x += width
            if index < values.count - 1 {
                x += itemSpacing
            }
            return frame
        }
    }

    private func totalWidth(for values: [MenuBarPopoverSection]) -> CGFloat {
        let chipsWidth = values.reduce(CGFloat.zero) { result, section in
            result + (chipViews[section]?.intrinsicContentSize.width
                ?? MenuBarSectionChipView.width(
                    for: section.title(language: language)
                ))
        }
        return chipsWidth + CGFloat(max(values.count - 1, 0)) * itemSpacing
    }
}

private final class MenuBarSectionChipView: NSView {
    private let backgroundView: NSView
    private let iconView: NSImageView
    private let label: NSTextField
    private let handleView: NSImageView
    private var isVisible: Bool
    private var isDragging = false

    init(
        section: MenuBarPopoverSection,
        title: String,
        isVisible: Bool
    ) {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = 14.5
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
        iconView = NSImageView(image: NSImage(
            systemSymbolName: section.systemImage,
            accessibilityDescription: nil
        ) ?? NSImage())
        label = NSTextField(labelWithString: title)
        handleView = NSImageView(image: NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: nil
        ) ?? NSImage())
        self.isVisible = isVisible
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .medium
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        handleView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 8,
            weight: .regular
        )
        handleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(handleView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            handleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            handleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 10)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        updateColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width(for: label.stringValue), height: 29)
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
                : NSColor.secondaryLabelColor.withAlphaComponent(isVisible ? 0.06 : 0.025)
        } else if let effectView = backgroundView as? NSVisualEffectView {
            effectView.layer?.backgroundColor = (isDragging
                ? NSColor.controlAccentColor.withAlphaComponent(0.16)
                : NSColor.secondaryLabelColor.withAlphaComponent(isVisible ? 0.04 : 0.015)
            ).cgColor
        }
    }

    func update(title: String, isVisible: Bool) {
        label.stringValue = title
        setAccessibilityLabel(title)
        self.isVisible = isVisible
        updateColors()
        invalidateIntrinsicContentSize()
        needsDisplay = true
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

    private func updateColors() {
        let contentColor: NSColor = isVisible ? .labelColor : .tertiaryLabelColor
        iconView.contentTintColor = contentColor
        label.textColor = contentColor
        handleView.contentTintColor = .tertiaryLabelColor
    }

    static func width(for title: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        let titleWidth = ceil((title as NSString).size(withAttributes: attributes).width)
        return titleWidth + 55
    }
}

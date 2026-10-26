import AppKit
import SwiftUI

/// Keep AppKit's native search appearance, editing and clear button.
struct LibrarySearchField: NSViewRepresentable {
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = 4
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = GlassSearchField()
        field.cell = GlassSearchFieldCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.controlSize = .large
        field.font = .systemFont(ofSize: 13)
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.focusRingType = .exterior
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("library.search")
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if context.coordinator.lastText != text {
            context.coordinator.lastText = text
            if field.stringValue != text { field.stringValue = text }
        }

        guard isFocused != (field.currentEditor() != nil) else { return }
        // Update first responder after SwiftUI finishes its current view update.
        DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator, let window = field.window else { return }
            if coordinator.parent.isFocused {
                if field.currentEditor() == nil { window.makeFirstResponder(field) }
            } else if let editor = field.currentEditor(), window.firstResponder === editor {
                window.makeFirstResponder(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LibrarySearchField
        var lastText: String

        init(parent: LibrarySearchField) {
            self.parent = parent
            lastText = parent.text
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            lastText = sender.stringValue
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { searchChanged(field) }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.isFocused = false
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

private final class GlassSearchField: NSSearchField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var focusRingMaskBounds: NSRect {
        bounds.insetBy(dx: -LibrarySearchField.horizontalPadding,
                       dy: (bounds.height - LibrarySearchField.height) / 2)
    }

    override func drawFocusRingMask() {
        let rect = focusRingMaskBounds
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
}

/// A bezel-free search field still needs the search cell's text inset when
/// AppKit creates the field editor. Otherwise editing starts beneath the icon.
private final class GlassSearchFieldCell: NSSearchFieldCell {
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView,
                   editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView,
                     editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

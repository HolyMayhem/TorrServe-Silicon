import AppKit
import SwiftUI

@MainActor
private final class SearchState: ObservableObject {
    @Published var text = ""
    @Published var focused = false
}

private struct SearchFixture: View {
    @ObservedObject var state: SearchState
    let width: CGFloat

    var body: some View {
        LibrarySearchField(placeholder: "Search", text: $state.text, isFocused: $state.focused)
            .padding(.horizontal, LibrarySearchField.horizontalPadding)
            .frame(width: width, height: LibrarySearchField.height)
            .padding(20)
    }
}

@main
struct LibrarySearchUIChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        func findSearch(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            return view.subviews.lazy.compactMap { findSearch(in: $0) }.first
        }

        for width: CGFloat in [175, 260, 286] {
            let state = SearchState()
            let host = NSHostingView(rootView: SearchFixture(state: state, width: width))
            let window = NSWindow(
                contentRect: NSRect(x: 30, y: 30, width: width + 40, height: 80),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            pump()
            host.layoutSubtreeIfNeeded()
            guard let field = findSearch(in: host) else { fatalError("Native search field missing") }
            expect(field.isEditable && field.isSelectable, "Search must remain editable")

            state.focused = true
            pump()
            guard let editor = field.currentEditor() as? NSTextView else { fatalError("Search focus failed") }
            let editingRect = editor.convert(editor.bounds, to: field)
            expect(abs(editingRect.minX - field.searchTextBounds.minX) <= 1,
                   "Focused text and cursor must align with the placeholder, after the search icon")
            expect(editingRect.minX > field.searchButtonBounds.midX + 6,
                   "The editor must not overlap the magnifying glass")
            expect(abs(field.focusRingMaskBounds.height - 28) < 0.5,
                   "Native focus ring must cover the full search capsule height")
            expect(abs(field.focusRingMaskBounds.width - width) < 0.5,
                   "Native focus ring must cover the full search capsule width")

            for character in "Archer" {
                editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                pump()
            }
            expect(state.text == "Archer" && field.stringValue == "Archer",
                   "Typing must update the binding without losing the first character")
            state.text = "The Thing"
            pump()
            expect(field.stringValue == "The Thing", "External query updates must reach the editor")
            guard let cancel = (field.cell as? NSSearchFieldCell)?.cancelButtonCell else {
                fatalError("Native clear button missing")
            }
            cancel.performClick(field)
            pump()
            expect(state.text.isEmpty && field.stringValue.isEmpty, "Clear must also clear the bound query")
            state.focused = false
            pump()
            expect(field.currentEditor() == nil, "Search must release focus when selecting a library item")

            let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0)!
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.postEvent(up, atStart: false)
            field.mouseDown(with: down)
            pump()
            guard let clickedEditor = field.currentEditor() as? NSTextView else {
                fatalError("Clicking must focus the search field")
            }
            expect(abs(clickedEditor.convert(clickedEditor.bounds, to: field).minX - field.searchTextBounds.minX) <= 1,
                   "Mouse focus must use the same text inset as keyboard focus")
        }
        print("Native library search UI: \(checks) checks passed")
    }
}

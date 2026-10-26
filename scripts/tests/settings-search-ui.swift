import AppKit
import SwiftUI

// The production search components only need a category's raw identifier.
enum SettingsCategory: String { case general }

@MainActor
private final class FixtureState: ObservableObject {
    @Published var indexOnly = true
    @Published var request: SettingsSearchRequest?
    var entries: [SettingsSearchEntry] = []
    var editorMounts = 0
    var targetFrame = CGRect.null
    var headingFrame = CGRect.null
}

private struct TargetFrameKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}
private struct HeadingFrameKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}

private struct SearchFixture: View {
    @ObservedObject var state: FixtureState
    private var form: some View {
        VStack(spacing: 0) {
            Text("Tall group")
                .frame(maxWidth: .infinity).frame(height: 32)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: HeadingFrameKey.self, value: geometry.frame(in: .named("viewport")))
                    }
                }
            ForEach(0..<40, id: \.self) { index in
                Text("Setting \(index)")
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .onAppear { state.editorMounts += 1 }
                    .background {
                        if index == 39 {
                            GeometryReader { geometry in
                                Color.clear.preference(key: TargetFrameKey.self, value: geometry.frame(in: .named("viewport")))
                            }
                        }
                    }
                    .searchableSetting("Setting \(index)")
            }
        }
        .searchableSettingsGroup("Tall group")
        .environment(\.settingsSearchCategory, .general)
    }
    var body: some View {
        ZStack {
            Color.white
            if state.indexOnly {
                // Same hidden, zero-size index layout as SettingsWindowView.
                form
                    .environment(\.isIndexingSettings, true)
                    .frame(width: 500)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .frame(width: 0, height: 0)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                SettingsSearchScrollView { form }
                    .environment(\.settingsSearchRequest, state.request)
            }
        }
        .coordinateSpace(name: "viewport")
        .frame(width: 500, height: 300)
        .onPreferenceChange(SettingsSearchEntriesKey.self) { state.entries = $0 }
        .onPreferenceChange(TargetFrameKey.self) { state.targetFrame = $0 }
        .onPreferenceChange(HeadingFrameKey.self) { state.headingFrame = $0 }
    }
}

@main
struct SettingsSearchUIChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        let state = FixtureState()
        let host = NSHostingView(rootView: SearchFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else {
                let details = "\(message); target=\(state.targetFrame), heading=\(state.headingFrame), entries=\(state.entries.count), active=\(NSApp.isActive), key=\(NSApp.keyWindow === window)\n"
                FileHandle.standardError.write(Data(details.utf8))
                fatalError(message)
            }
        }
        func wait(_ message: String, until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(8)
            while !condition(), Date() < deadline {
                host.layoutSubtreeIfNeeded()
                while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            expect(condition(), message)
        }
        wait("Hidden index must emit all rows and the group") { state.entries.count == 41 }
        expect(state.entries.contains { $0.title == "Setting 39" && $0.group == "Tall group" }, "Include settings below the viewport")
        expect(state.entries.contains { $0.title == "Tall group" && $0.isGroup }, "Register group destinations explicitly")
        expect(state.editorMounts == 0, "Indexing must never mount editor lifecycle callbacks")

        state.indexOnly = false
        wait("Real form must mount") { !state.targetFrame.isNull && state.targetFrame.minY > 300 }
        let target = state.entries.first { $0.title == "Setting 39" }!
        state.request = SettingsSearchRequest(entry: target)
        wait("Row search must scroll the last setting fully into view") {
            !state.targetFrame.isNull && state.targetFrame.minY >= -1 && state.targetFrame.maxY <= 301
        }
        let group = state.entries.first { $0.isGroup }!
        state.request = SettingsSearchRequest(entry: group)
        wait("A tall group must scroll to its heading, not its middle") {
            !state.headingFrame.isNull && abs(state.headingFrame.minY) < 2
        }
        state.request = SettingsSearchRequest(entry: target)
        wait("A fresh revision must scroll the same result again") {
            !state.targetFrame.isNull && state.targetFrame.minY >= -1 && state.targetFrame.maxY <= 301
        }
        expect(state.editorMounts == 40, "Navigation must preserve editor identities")
        print("Native settings search UI: \(checks) checks passed")
    }
}

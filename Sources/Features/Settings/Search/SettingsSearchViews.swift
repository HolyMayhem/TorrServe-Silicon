import SwiftUI

private struct SettingsSearchCategoryKey: EnvironmentKey {
    static let defaultValue: SettingsCategory? = nil
}
private struct SettingsSearchGroupKey: EnvironmentKey {
    static let defaultValue = ""
}
private struct SettingsSearchIndexingKey: EnvironmentKey {
    static let defaultValue = false
}
private struct SettingsSearchRequestKey: EnvironmentKey {
    static let defaultValue: SettingsSearchRequest? = nil
}
private struct SettingsSearchRevealKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsSearchCategory: SettingsCategory? {
        get { self[SettingsSearchCategoryKey.self] }
        set { self[SettingsSearchCategoryKey.self] = newValue }
    }
    var settingsSearchGroup: String {
        get { self[SettingsSearchGroupKey.self] }
        set { self[SettingsSearchGroupKey.self] = newValue }
    }
    var isIndexingSettings: Bool {
        get { self[SettingsSearchIndexingKey.self] }
        set { self[SettingsSearchIndexingKey.self] = newValue }
    }
    var settingsSearchRequest: SettingsSearchRequest? {
        get { self[SettingsSearchRequestKey.self] }
        set { self[SettingsSearchRequestKey.self] = newValue }
    }
    var settingsSearchRevealSection: String? {
        get { self[SettingsSearchRevealKey.self] }
        set { self[SettingsSearchRevealKey.self] = newValue }
    }
}

struct SettingsSearchEntriesKey: PreferenceKey {
    static let defaultValue: [SettingsSearchEntry] = []
    static func reduce(value: inout [SettingsSearchEntry], nextValue: () -> [SettingsSearchEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct SearchableSetting: ViewModifier {
    let title: String
    let isGroup: Bool
    @Environment(\.settingsSearchCategory) private var category
    @Environment(\.settingsSearchGroup) private var group
    @Environment(\.isIndexingSettings) private var isIndexing
    @Environment(\.settingsSearchRequest) private var request
    @Environment(\.settingsSearchRevealSection) private var revealSection

    func body(content: Content) -> some View {
        if let category {
            let entry = SettingsSearchEntry(
                category: category.rawValue, group: isGroup ? "" : group,
                title: title, revealSection: revealSection
            )
            if isIndexing && !isGroup {
                // Do not mount editors, actions or their lifecycle callbacks in the index.
                Color.clear.frame(height: 0)
                    .preference(key: SettingsSearchEntriesKey.self, value: [entry])
            } else {
                content
                    .environment(\.settingsSearchGroup, isGroup ? title : group)
                    .id(entry.id)
                    .background {
                        if request?.entry.id == entry.id {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay {
                        if request?.entry.id == entry.id {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .background {
                        Color.clear.preference(key: SettingsSearchEntriesKey.self, value: [entry])
                    }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Use the visible title once. Common row builders apply this automatically.
    func searchableSetting(_ title: String) -> some View {
        modifier(SearchableSetting(title: title, isGroup: false))
    }
    func searchableSettingsGroup(_ title: String) -> some View {
        modifier(SearchableSetting(title: title, isGroup: true))
    }
}

struct SettingsSearchScrollView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    @Environment(\.settingsSearchRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availableIDs = Set<SettingsSearchEntry.ID>()

    private struct ScrollTask: Equatable {
        let revision: UUID?
        let isAvailable: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onPreferenceChange(SettingsSearchEntriesKey.self) { entries in
                    availableIDs = Set(entries.map(\.id))
                }
                .task(id: ScrollTask(
                    revision: request?.revision,
                    isAvailable: request.map { availableIDs.contains($0.entry.id) } ?? false
                )) {
                    guard let request, availableIDs.contains(request.entry.id) else { return }
                    // Preferences confirm the destination has mounted, including disclosures.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        proxy.scrollTo(request.entry.id, anchor: .center)
                    }
                }
        }
    }
}

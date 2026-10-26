import Foundation

/// Titles come from the same components that render settings, never a second catalogue.
struct SettingsSearchEntry: Hashable, Identifiable {
    let category: String
    let group: String
    let title: String
    var revealSection: String? = nil

    struct ID: Hashable {
        let category: String
        let group: String
        let title: String
    }

    var id: ID { ID(category: category, group: group, title: title) }
}

struct SettingsSearchRequest: Equatable {
    let entry: SettingsSearchEntry
    let revision = UUID()
}

enum SettingsSearchIndex {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }

    static func results(for query: String, in entries: [SettingsSearchEntry]) -> [SettingsSearchEntry] {
        let words = normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var seen = Set<SettingsSearchEntry.ID>()
        return entries.filter { entry in
            let title = normalized(entry.title)
            // A one-row group may repeat its heading; its group is already a destination.
            return entry.group != entry.title && words.allSatisfy { title.contains($0) } && seen.insert(entry.id).inserted
        }.sorted { lhs, rhs in
            let left = normalized(lhs.title)
            let right = normalized(rhs.title)
            let phrase = words.joined(separator: " ")
            if (left == phrase) != (right == phrase) { return left == phrase }
            if left.hasPrefix(phrase) != right.hasPrefix(phrase) { return left.hasPrefix(phrase) }
            return (lhs.category, lhs.group, left) < (rhs.category, rhs.group, right)
        }
    }
}

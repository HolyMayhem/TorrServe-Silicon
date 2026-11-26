import Foundation

actor CatalogCache {
    enum Key: Hashable, Sendable {
        case page(CatalogListing, Int, String, CatalogSource, CatalogConnection)
        case details(CatalogIdentity, String, CatalogTMDBConnection)
        case genres(MediaKind, String, CatalogTMDBConnection)
    }

    enum Value: Sendable {
        case page(CatalogPage)
        case details(CatalogDetails)
        case genres([CatalogGenre])
    }

    private struct Entry {
        let value: Value
        let stored: Date
    }

    private var entries: [Key: Entry] = [:]
    private let capacity = 180

    func value(for key: Key, allowingStale: Bool = false) -> Value? {
        guard let entry = entries[key] else { return nil }
        let age = Date.now.timeIntervalSince(entry.stored)
        guard age < (allowingStale ? 86_400 : 900) else { return nil }
        return entry.value
    }

    func save(_ value: Value, for key: Key) {
        if entries.count >= capacity, entries[key] == nil,
           let oldest = entries.min(by: { $0.value.stored < $1.value.stored })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = Entry(value: value, stored: .now)
    }
}

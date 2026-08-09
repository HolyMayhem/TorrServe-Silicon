import Foundation

enum SearchSortField: String, CaseIterable, Identifiable {
    case seeders
    case peers
    case size

    var id: String { rawValue }
}

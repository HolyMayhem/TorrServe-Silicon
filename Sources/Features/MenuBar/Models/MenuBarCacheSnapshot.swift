import Foundation

/// The sum of the actual buffers belonging to the active torrents, not app RAM
/// or disk usage. A missing/failed response is unavailable rather than zero.
struct MenuBarCacheSnapshot: Equatable {
    let used: Int64
    let capacity: Int64

    static let empty = MenuBarCacheSnapshot(used: 0, capacity: 0)

    static func aggregate(_ buffers: [(used: Int64, capacity: Int64)]) -> Self? {
        var total = Self.empty
        for buffer in buffers {
            guard buffer.used >= 0, buffer.capacity >= buffer.used else { return nil }
            let used = total.used.addingReportingOverflow(buffer.used)
            let capacity = total.capacity.addingReportingOverflow(buffer.capacity)
            guard !used.overflow, !capacity.overflow else { return nil }
            total = Self(used: used.partialValue, capacity: capacity.partialValue)
        }
        return total
    }

    var fraction: Double {
        capacity > 0 ? Double(used) / Double(capacity) : 0
    }

    var formattedUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useMB, .useGB]
        return "\(formatter.string(fromByteCount: used)) / \(formatter.string(fromByteCount: capacity))"
    }
}

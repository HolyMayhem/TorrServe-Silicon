import Foundation

enum SpeedDisplayUnit: String, CaseIterable {
    case automatic
    case megabytes
    case megabits
}

enum SpeedFormatter {
    static func string(
        bytesPerSecond: Double,
        unit: SpeedDisplayUnit
    ) -> String {
        let safeValue = max(bytesPerSecond, 0)

        switch unit {
        case .automatic:
            if safeValue >= 1024 * 1024 {
                return String(format: "%.1f MB/s", safeValue / 1024 / 1024)
            }
            return String(format: "%.0f KB/s", safeValue / 1024)

        case .megabytes:
            return String(format: "%.2f MB/s", safeValue / 1024 / 1024)

        case .megabits:
            return String(format: "%.1f Mbit/s", safeValue * 8 / 1_000_000)
        }
    }
}

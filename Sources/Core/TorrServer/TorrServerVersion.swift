import Foundation

struct TorrServerVersion: Comparable {
    let displayName: String
    private let components: [Int]

    init?(_ text: String) {
        let pattern = #"(?i)matrix\.([0-9]+(?:\.[0-9]+)*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let versionNumber = String(text[versionRange])
        let numbers = versionNumber.split(separator: ".")
        let parsedComponents = numbers.compactMap { Int($0) }
        guard parsedComponents.count == numbers.count else { return nil }

        displayName = "MatriX.\(versionNumber)"
        components = parsedComponents
    }

    init?(releaseTag: String) {
        guard let version = Self(releaseTag),
              version.displayName.caseInsensitiveCompare(releaseTag) == .orderedSame else { return nil }
        self = version
    }

    static func == (lhs: TorrServerVersion, rhs: TorrServerVersion) -> Bool {
        compare(lhs.components, rhs.components) == .orderedSame
    }

    static func < (lhs: TorrServerVersion, rhs: TorrServerVersion) -> Bool {
        compare(lhs.components, rhs.components) == .orderedAscending
    }

    private static func compare(
        _ lhs: [Int],
        _ rhs: [Int]
    ) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}

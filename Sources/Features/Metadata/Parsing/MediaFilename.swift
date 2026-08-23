import Foundation

enum MediaFilename {
    private static let removableExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "wmv", "webm", "ts", "m2ts", "torrent"
    ]

    static func titleSource(from value: String) -> String {
        let path = value as NSString
        guard removableExtensions.contains(path.pathExtension.lowercased()) else {
            return value
        }
        return (path.lastPathComponent as NSString).deletingPathExtension
    }
}

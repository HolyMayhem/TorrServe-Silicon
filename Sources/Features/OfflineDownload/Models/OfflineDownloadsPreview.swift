import Combine
import Foundation

/// Developer-only records. Never written to download history or the filesystem.
final class OfflineDownloadsPreview: ObservableObject {
    @Published private(set) var records: [OfflineDownloadRecord] = []

    @MainActor func populate(isRussian: Bool) {
        let now = Date()
        records = (1...15).flatMap { index -> [OfflineDownloadRecord] in
            let number = String(format: "%02d", index)
            let isSeries = index > 12
            let title = isSeries
                ? (isRussian ? "Демо-сериал \(number)" : "Demo Series \(number)")
                : (isRussian ? "Демо-фильм \(number)" : "Demo Movie \(number)")
            let media = OfflineMediaInfo(id: "demo:\(index)", title: title, posterURL: nil, isSeries: isSeries, torrentHash: nil)
            return (1...(isSeries ? 4 : 1)).map { episode in
                let season = episode > 2 ? 2 : 1
                let filename = isSeries ? "\(title).S0\(season)E0\((episode - 1) % 2 + 1).mkv" : "\(title).mkv"
                let url = URL(string: "torrserve-demo://offline/\(index)")!.appendingPathComponent(filename)
                return OfflineDownloadRecord(
                    sourceURL: url, destinationURL: url,
                    expectedLength: Int64(2 + index % 6) * 1_073_741_824 + Int64(episode) * 16_777_216,
                    completedAt: now.addingTimeInterval(-Double(index) * 60 - Double(episode)),
                    media: media
                )
            }
        }
    }

    @MainActor func contains(_ record: OfflineDownloadRecord) -> Bool {
        records.contains { $0.destinationURL == record.destinationURL }
    }

    @MainActor func remove(_ record: OfflineDownloadRecord) {
        records.removeAll { $0.destinationURL == record.destinationURL }
    }

    @MainActor func clear() { records = [] }
}

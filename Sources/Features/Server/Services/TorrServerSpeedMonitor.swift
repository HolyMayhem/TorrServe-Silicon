import Foundation

final class TorrServerSpeedMonitor {
    var onSpeedChange: ((Double?) -> Void)?

    private let statURL = URL(string: "http://127.0.0.1:8090/stat")!
    private var timer: Timer?
    private var previousSample: (bytes: Int64, date: Date)?
    private var isRequestInFlight = false

    func start() {
        guard timer == nil else { return }

        previousSample = nil
        fetchStat()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.fetchStat()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSample = nil
        isRequestInFlight = false
        onSpeedChange?(nil)
    }

    private func fetchStat() {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true

        var request = URLRequest(url: statURL)
        request.timeoutInterval = 1.5

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }

            let now = Date()
            let bytes = data
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(Self.extractReadDataBytes)

            DispatchQueue.main.async {
                self.isRequestInFlight = false

                guard let bytes else {
                    self.previousSample = nil
                    self.onSpeedChange?(nil)
                    return
                }

                let speed: Double
                if let previous = self.previousSample {
                    let interval = max(now.timeIntervalSince(previous.date), 0.1)
                    speed = max(0, Double(bytes - previous.bytes) / interval)
                } else {
                    speed = 0
                }

                self.previousSample = (bytes, now)
                self.onSpeedChange?(speed)
            }
        }.resume()
    }

    private static func extractReadDataBytes(from text: String) -> Int64? {
        extractCounter(named: "BytesReadData", from: text)
            ?? extractCounter(named: "BytesReadUsefulData", from: text)
            ?? extractCounter(named: "BytesRead", from: text)
    }

    private static func extractCounter(named name: String, from text: String) -> Int64? {
        let pattern = "\(name):\\s*\\([^)]*\\)\\s*(\\d+)"

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int64(text[range])
    }
}

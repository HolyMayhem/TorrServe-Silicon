import Foundation

enum TorrentFileError: String {
    case empty, html, json, xml, bencode, missingInfo
}

enum TorrentFileValidator {
    static func validate(_ data: Data) throws {
        guard !data.isEmpty else { throw TorrentAddError.invalidTorrent(.empty) }

        // Parse bytes directly. Bencoded strings such as pieces can contain arbitrary binary data.
        let failure: TorrentFileError? = data.withUnsafeBytes { bytes in
            var parser = BencodeScanner(bytes: bytes)
            return parser.torrentError()
        }
        guard failure != .bencode else {
            let prefix = String(decoding: data.prefix(512), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
                .lowercased()
            if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") ||
                prefix.hasPrefix("<head") || prefix.hasPrefix("<body") || prefix.hasPrefix("<form") {
                throw TorrentAddError.invalidTorrent(.html)
            }
            if prefix.hasPrefix("<") { throw TorrentAddError.invalidTorrent(.xml) }
            if prefix.hasPrefix("{") || prefix.hasPrefix("[") || prefix == "null" {
                throw TorrentAddError.invalidTorrent(.json)
            }
            throw TorrentAddError.invalidTorrent(.bencode)
        }
        if let failure { throw TorrentAddError.invalidTorrent(failure) }
    }
}

private struct BencodeScanner {
    let bytes: UnsafeRawBufferPointer
    private var index = 0
    private var rootHasInfo = false

    init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    mutating func torrentError() -> TorrentFileError? {
        guard current == 100, consumeValue(depth: 0), index == bytes.count else { return .bencode }
        return rootHasInfo ? nil : .missingInfo
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func consumeValue(depth: Int) -> Bool {
        guard depth <= 128 else { return false }
        switch current {
        case 100: // d
            index += 1
            var previousKey: Range<Int>?
            while current != 101 {
                guard let key = consumeString() else { return false }
                if let previousKey, !bytes[previousKey].lexicographicallyPrecedes(bytes[key]) {
                    return false
                }
                previousKey = key
                if depth == 0, bytes[key].elementsEqual([105, 110, 102, 111]) {
                    rootHasInfo = current == 100 && index + 1 < bytes.count && bytes[index + 1] != 101
                }
                guard consumeValue(depth: depth + 1) else { return false }
            }
        case 108: // l
            index += 1
            while current != 101 {
                guard consumeValue(depth: depth + 1) else { return false }
            }
        case 105: // i
            index += 1
            let negative = current == 45
            if negative { index += 1 }
            guard let digit = current, (48...57).contains(digit) else { return false }
            index += 1
            if digit == 48 {
                guard !negative else { return false }
            } else {
                while let digit = current, (48...57).contains(digit) { index += 1 }
            }
            guard current == 101 else { return false }
        default:
            return consumeString() != nil
        }
        index += 1
        return true
    }

    private mutating func consumeString() -> Range<Int>? {
        guard let first = current, (48...57).contains(first) else { return nil }
        let start = index
        var length = 0
        while let digit = current, (48...57).contains(digit) {
            guard first != 48 || index == start else { return nil }
            let (shifted, shiftOverflow) = length.multipliedReportingOverflow(by: 10)
            let (updated, addOverflow) = shifted.addingReportingOverflow(Int(digit - 48))
            guard !shiftOverflow, !addOverflow, updated <= bytes.count else { return nil }
            length = updated
            index += 1
        }
        guard current == 58, length < bytes.count - index else { return nil }
        index += 1
        let content = index..<(index + length)
        index += length
        return content
    }
}

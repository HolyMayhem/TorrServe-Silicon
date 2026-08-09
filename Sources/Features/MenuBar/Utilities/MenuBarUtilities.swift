import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin

enum QRCodeGenerator {
    static func image(for string: String, size: CGFloat = 180) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = max(size / outputImage.extent.width, 1)
        let scaled = outputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: size, height: size)
        )
    }
}

enum LocalWebUIAddress {
    static func url() -> URL {
        let address = preferredIPv4Address() ?? "localhost"
        return URL(string: "http://\(address):8090") ?? webUIURL
    }

    private static func preferredIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var candidates: [(priority: Int, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard
                let addressPointer = current.pointee.ifa_addr,
                addressPointer.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let interfaceName = String(cString: current.pointee.ifa_name)
            guard interfaceName != "lo0" else { continue }

            var socketAddress = UnsafeRawPointer(addressPointer)
                .assumingMemoryBound(to: sockaddr_in.self)
                .pointee
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

            guard inet_ntop(
                AF_INET,
                &socketAddress.sin_addr,
                &buffer,
                socklen_t(INET_ADDRSTRLEN)
            ) != nil else {
                continue
            }

            let address = String(cString: buffer)
            guard !address.hasPrefix("169.254.") else { continue }

            let priority: Int
            switch interfaceName {
            case "en0": priority = 0
            case "en1": priority = 1
            default: priority = 2
            }
            candidates.append((priority, address))
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }
}

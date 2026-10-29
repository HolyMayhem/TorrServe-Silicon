import Darwin
import Foundation

public enum TelemetryEnvironment {
    /// Debug is deliberately incapable of sending to production, even with a copied plist.
    public static func endpoint(debug: Bool, bundle: Bundle = .main,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if debug {
            guard let value = environment["TORRSERVE_TELEMETRY_DEBUG_URL"],
                  let url = URL(string: value), url.scheme == "http",
                  ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host ?? ""),
                  url.path == "/v1/heartbeat", url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return nil }
            return url
        }
        guard let value = bundle.object(forInfoDictionaryKey: "TorrServeTelemetryEndpoint") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.path == "/v1/heartbeat", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    public static func snapshot(bundle: Bundle = .main) -> TelemetrySnapshot {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let arm = sysctlInt("hw.optional.arm64") == 1
        let rawModel = sysctlString("machdep.cpu.brand_string")
        return TelemetrySnapshot(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            cpuArchitecture: arm ? "arm64" : "x86_64",
            cpuModel: normalizedCPU(rawModel, arm: arm)
        )
    }

    /// Only a CPU family is sent, never device serial, board ID, host name, or sysctl dump.
    /// hw.optional.arm64 also identifies Apple Silicon when running under Rosetta.
    public static func normalizedCPU(_ raw: String, arm: Bool) -> String {
        if arm {
            let pattern = #"^Apple M[1-9][0-9]?( (Pro|Max|Ultra))?$"#
            return raw.range(of: pattern, options: .regularExpression) != nil ? raw : "Apple Silicon (other)"
        }
        if raw.localizedCaseInsensitiveContains("Xeon") { return "Intel Xeon" }
        for family in ["i3", "i5", "i7", "i9"] where raw.contains(family + "-") {
            return "Intel Core \(family)"
        }
        return "Intel (other)"
    }

    private static func sysctlInt(_ name: String) -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

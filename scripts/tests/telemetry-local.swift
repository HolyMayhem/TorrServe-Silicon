// Run only against a loopback Worker; uses a disposable defaults domain.
import Foundation

@main
struct LocalTelemetrySmoke {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = TelemetryEnvironment.endpoint(debug: true, environment: environment) else {
            fatalError("Set TORRSERVE_TELEMETRY_DEBUG_URL to the loopback /v1/heartbeat endpoint")
        }
        let suite = "Telemetry.LocalSmoke." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TelemetryClient(defaults: defaults, namespace: "debug", endpoint: endpoint,
                                     snapshot: { TelemetryEnvironment.snapshot() })
        await client.heartbeatIfNeeded()
        guard defaults.object(forKey: "Telemetry.debug.lastSuccess") != nil else {
            fatalError("Local Worker did not acknowledge the native URLSession heartbeat")
        }
        await client.heartbeatIfNeeded()
        print("PASS: native URLSession heartbeat acknowledged by local Worker; immediate replay suppressed.")
    }
}

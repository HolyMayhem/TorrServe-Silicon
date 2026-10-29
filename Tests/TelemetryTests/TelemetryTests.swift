import Foundation
import XCTest
@testable import Telemetry

actor RecordingTransport: TelemetryTransport {
    var requests: [URLRequest] = []
    var fail = false
    var status = 204
    func setFail(_ value: Bool) { fail = value }
    func setStatus(_ value: Int) { status = value }
    func send(_ request: URLRequest) async throws -> Int {
        requests.append(request)
        if fail { throw URLError(.notConnectedToInternet) }
        return status
    }
    func recorded() -> [URLRequest] { requests }
}

actor SuspendedTransport: TelemetryTransport {
    var started = false
    var cancelled = false
    func hasStarted() -> Bool { started }
    func wasCancelled() -> Bool { cancelled }
    func send(_ request: URLRequest) async throws -> Int {
        started = true
        do { try await Task.sleep(for: .seconds(30)) }
        catch { cancelled = true; throw error }
        return 204
    }
}

final class TelemetryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    override func setUp() {
        suite = "TelemetryTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func client(_ transport: RecordingTransport, version: String = "2.8.0", namespace: String = "test", endpoint: URL? = URL(string: "http://localhost:8787/v1/heartbeat")) -> TelemetryClient {
        TelemetryClient(defaults: defaults, namespace: namespace, endpoint: endpoint, transport: transport) {
            TelemetrySnapshot(appVersion: version, macOSVersion: "15.7.0", cpuArchitecture: "arm64", cpuModel: "Apple M4 Pro")
        }
    }
    private func payload(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    func testRelaunchKeepsIdentityAndDeduplicatesAcrossLaunches() async throws {
        let transport = RecordingTransport()
        await client(transport).heartbeatIfNeeded(now: base)
        await client(transport).heartbeatIfNeeded(now: base.addingTimeInterval(3600))
        await client(transport).heartbeatIfNeeded(now: base.addingTimeInterval(86400))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        let first = try payload(requests[0]), second = try payload(requests[1])
        XCTAssertEqual(first["installationID"] as? String, second["installationID"] as? String)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(first["installationID"] as? String)))
        XCTAssertEqual(Set(first.keys), Set(["schemaVersion","installationID","appVersion","macOSVersion","cpuArchitecture","cpuModel"]))
    }
    func testVersionUpdatePreservesIDAndWaitsUntilNextDay() async throws {
        let transport = RecordingTransport()
        await client(transport, version: "2.8.0").heartbeatIfNeeded(now: base)
        await client(transport, version: "2.9.0").heartbeatIfNeeded(now: base.addingTimeInterval(60))
        await client(transport, version: "2.9.0").heartbeatIfNeeded(now: base.addingTimeInterval(86400))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try payload(requests[1])["appVersion"] as? String, "2.9.0")
        XCTAssertEqual(try payload(requests[0])["installationID"] as? String, try payload(requests[1])["installationID"] as? String)
    }
    func testOfflineFailureIsSilentAndThrottledAcrossRelaunch() async {
        let transport = RecordingTransport(); await transport.setFail(true)
        await client(transport).heartbeatIfNeeded(now: base)
        await client(transport).heartbeatIfNeeded(now: base.addingTimeInterval(60))
        await transport.setFail(false)
        await client(transport).heartbeatIfNeeded(now: base.addingTimeInterval(86400))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotNil(defaults.object(forKey: "Telemetry.test.lastSuccess"))
    }
    func testDisabledDoesNotGenerateIdentityOrSend() async {
        let transport = RecordingTransport(), service = client(transport)
        await service.setEnabled(false)
        await service.heartbeatIfNeeded(now: base)
        await client(transport).heartbeatIfNeeded(now: base.addingTimeInterval(86400))
        let requests = await transport.recorded()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(defaults.object(forKey: "Telemetry.test.installationID"))
        await service.setEnabled(true)
        await service.heartbeatIfNeeded(now: base)
        let enabledRequests = await transport.recorded()
        XCTAssertEqual(enabledRequests.count, 1)
    }
    func testConcurrentActivationSendsOnlyOnce() async {
        let transport = RecordingTransport(), service = client(transport)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { await service.heartbeatIfNeeded(now: self.base) } }
        }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
    }
    func testClockRollbackCannotCauseRepeatedSends() async {
        let transport = RecordingTransport(), service = client(transport)
        await service.heartbeatIfNeeded(now: base)
        await service.heartbeatIfNeeded(now: base.addingTimeInterval(-86400))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
    }
    func testEnvironmentAndIdentityAreIsolated() async throws {
        let transport = RecordingTransport()
        await client(transport, namespace: "debug").heartbeatIfNeeded(now: base)
        await client(transport, namespace: "production").heartbeatIfNeeded(now: base)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(try payload(requests[0])["installationID"] as? String, try payload(requests[1])["installationID"] as? String)
        XCTAssertNil(TelemetryEnvironment.endpoint(debug: true, environment: [:]))
        XCTAssertNil(TelemetryEnvironment.endpoint(debug: true, environment: ["TORRSERVE_TELEMETRY_DEBUG_URL":"https://example.com/v1/heartbeat"]))
        XCTAssertNil(TelemetryEnvironment.endpoint(debug: true, environment: ["TORRSERVE_TELEMETRY_DEBUG_URL":"http://localhost.evil.test/v1/heartbeat"]))
        XCTAssertNotNil(TelemetryEnvironment.endpoint(debug: true, environment: ["TORRSERVE_TELEMETRY_DEBUG_URL":"http://127.0.0.1:8787/v1/heartbeat"]))
    }
    func testMissingEndpointDoesNotGenerateIdentity() async {
        let transport = RecordingTransport()
        await client(transport, endpoint: nil).heartbeatIfNeeded(now: base)
        XCTAssertNil(defaults.object(forKey: "Telemetry.test.installationID"))
        let requests = await transport.recorded()
        XCTAssertTrue(requests.isEmpty)
    }
    func testHTTPFailureDoesNotBecomeSuccessOrCauseImmediateRetry() async {
        let transport = RecordingTransport()
        await transport.setStatus(503)
        let service = client(transport)
        await service.heartbeatIfNeeded(now: base)
        await service.heartbeatIfNeeded(now: base.addingTimeInterval(60))
        XCTAssertNil(defaults.object(forKey: "Telemetry.test.lastSuccess"))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].timeoutInterval, 10)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "User-Agent"), "TorrServe-Telemetry/1")
    }
    func testDisablingCancelsInFlightRequest() async {
        let transport = SuspendedTransport()
        let service = TelemetryClient(defaults: defaults, namespace: "test",
            endpoint: URL(string: "http://localhost:8787/v1/heartbeat"), transport: transport,
            snapshot: { TelemetrySnapshot(appVersion: "2.8.0", macOSVersion: "15.7.0", cpuArchitecture: "arm64", cpuModel: "Apple M4") })
        let task = Task { await service.heartbeatIfNeeded(now: base) }
        for _ in 0..<10000 {
            if await transport.hasStarted() { break }
            await Task.yield()
        }
        let started = await transport.hasStarted()
        XCTAssertTrue(started)
        await service.setEnabled(false)
        await task.value
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
        XCTAssertNil(defaults.object(forKey: "Telemetry.test.lastSuccess"))
    }
    @MainActor
    func testLifecycleSwitchPersistsImmediatelyAndCancelsNetwork() async {
        let transport = SuspendedTransport()
        let controller = TelemetryController(defaults: defaults, namespace: "test",
            endpoint: URL(string: "http://localhost:8787/v1/heartbeat"), transport: transport,
            snapshot: { TelemetrySnapshot(appVersion: "2.8.0", macOSVersion: "15.7.0", cpuArchitecture: "arm64", cpuModel: "Apple M4") })
        controller.setEnabled(true)
        for _ in 0..<10000 {
            if await transport.hasStarted() { break }
            await Task.yield()
        }
        let started = await transport.hasStarted()
        XCTAssertTrue(started)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isEnabled)
        for _ in 0..<10000 {
            if await transport.wasCancelled() { break }
            await Task.yield()
        }
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
        XCTAssertFalse(defaults.bool(forKey: "Telemetry.test.enabled"))
    }
    func testAppleSiliconAndIntelNormalizeOnlyCPUFamily() {
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("Apple M4 Pro", arm: true), "Apple M4 Pro")
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("Apple M5 Ultra", arm: true), "Apple M5 Ultra")
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("unknown host-name serial", arm: true), "Apple Silicon (other)")
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz", arm: false), "Intel Core i7")
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("Intel(R) Xeon(R) W-2140B", arm: false), "Intel Xeon")
        XCTAssertEqual(TelemetryEnvironment.normalizedCPU("unknown", arm: false), "Intel (other)")
        XCTAssertTrue(["arm64","x86_64"].contains(TelemetryEnvironment.snapshot().cpuArchitecture))
    }
}

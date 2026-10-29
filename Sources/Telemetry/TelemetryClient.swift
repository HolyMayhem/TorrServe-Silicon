import Foundation

public struct TelemetrySnapshot: Codable, Equatable, Sendable {
    public let appVersion: String
    public let macOSVersion: String
    public let cpuArchitecture: String
    public let cpuModel: String

    public init(appVersion: String, macOSVersion: String, cpuArchitecture: String, cpuModel: String) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.cpuArchitecture = cpuArchitecture
        self.cpuModel = cpuModel
    }
}

struct TelemetryHeartbeat: Encodable {
    let schemaVersion = 1
    let installationID: String
    let appVersion: String
    let macOSVersion: String
    let cpuArchitecture: String
    let cpuModel: String
}

/// URLSession owns no cookies, disk cache, credentials, or identifying app User-Agent.
public protocol TelemetryTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Int
}

public final class TelemetryURLSessionTransport: TelemetryTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "TorrServe-Telemetry/1"]
        session = URLSession(configuration: configuration, delegate: TelemetryRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> Int {
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

private final class TelemetryRedirectPolicy: NSObject, URLSessionTaskDelegate {
    // Never forward the installation ID to another origin via redirects.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// All identity and send state lives in this actor; no playback/server/update dependencies.
public actor TelemetryClient {
    public static let minimumInterval: TimeInterval = 24 * 60 * 60
    private let defaults: UserDefaults
    private let prefix: String
    private let endpoint: URL?
    private let transport: any TelemetryTransport
    private let snapshot: @Sendable () -> TelemetrySnapshot
    private var inFlight: Task<Int, Error>?
    private var revision = 0

    public init(defaults: UserDefaults, namespace: String, endpoint: URL?,
                transport: any TelemetryTransport = TelemetryURLSessionTransport(),
                snapshot: @escaping @Sendable () -> TelemetrySnapshot) {
        self.defaults = defaults
        self.prefix = "Telemetry.\(namespace)."
        self.endpoint = endpoint
        self.transport = transport
        self.snapshot = snapshot
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: prefix + "enabled")
        if !enabled {
            revision += 1
            inFlight?.cancel()
            inFlight = nil
        }
    }

    /// A failure is silent and retried at the next daily opportunity. Persist BEFORE awaiting
    /// the network, so relaunches, failures, and concurrent activation events cannot spam it.
    public func heartbeatIfNeeded(now: Date = Date()) async {
        guard defaults.object(forKey: prefix + "enabled") as? Bool ?? true,
              let endpoint, inFlight == nil, !Task.isCancelled else { return }
        if let previous = defaults.object(forKey: prefix + "lastAttempt") as? Date,
           now.timeIntervalSince(previous) < Self.minimumInterval { return }

        let installationID: String
        if let saved = defaults.string(forKey: prefix + "installationID"), UUID(uuidString: saved) != nil {
            installationID = saved
        } else {
            installationID = UUID().uuidString.lowercased()
            defaults.set(installationID, forKey: prefix + "installationID")
        }
        let metadata = snapshot()
        let payload = TelemetryHeartbeat(installationID: installationID, appVersion: metadata.appVersion,
                                        macOSVersion: metadata.macOSVersion, cpuArchitecture: metadata.cpuArchitecture,
                                        cpuModel: metadata.cpuModel)
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TorrServe-Telemetry/1", forHTTPHeaderField: "User-Agent")
        defaults.set(now, forKey: prefix + "lastAttempt")
        let currentRevision = revision
        let transport = self.transport
        let task = Task { try await transport.send(request) }
        inFlight = task
        let status = await withTaskCancellationHandler {
            try? await task.value
        } onCancel: {
            task.cancel()
        }
        guard revision == currentRevision else { return }
        inFlight = nil
        if status == 204, !task.isCancelled {
            defaults.set(now, forKey: prefix + "lastSuccess")
        }
    }
}

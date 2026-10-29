import Foundation

/// Small lifecycle adapter. The host only starts it and binds the preference.
@MainActor
public final class TelemetryController {
    private let defaults: UserDefaults
    private let enabledKey: String
    private let client: TelemetryClient
    private var timer: Timer?
    private var heartbeatTask: Task<Void, Never>?
    private var preferenceTask: Task<Void, Never>?

    public var isEnabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }

    public convenience init() {
        #if DEBUG
        let debug = true
        let namespace = "debug"
        #else
        let debug = false
        let namespace = "production"
        #endif
        self.init(defaults: .standard, namespace: namespace,
                  endpoint: TelemetryEnvironment.endpoint(debug: debug),
                  snapshot: { TelemetryEnvironment.snapshot() })
    }

    init(defaults: UserDefaults, namespace: String, endpoint: URL?,
         transport: any TelemetryTransport = TelemetryURLSessionTransport(),
         snapshot: @escaping @Sendable () -> TelemetrySnapshot) {
        self.defaults = defaults
        enabledKey = "Telemetry.\(namespace).enabled"
        client = TelemetryClient(defaults: defaults, namespace: namespace, endpoint: endpoint,
                                 transport: transport, snapshot: snapshot)
    }

    public func start() {
        guard timer == nil else { return }
        // Delayed, utility-priority send; never gate app launch on network availability.
        heartbeatTask = Task(priority: .utility) { [client] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await client.heartbeatIfNeeded()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activityOpportunity() }
        }
        timer?.tolerance = 300
    }

    public func activityOpportunity() {
        guard isEnabled else { return }
        let previous = heartbeatTask
        let preference = preferenceTask
        heartbeatTask = Task(priority: .utility) { [client] in
            await previous?.value
            await preference?.value
            guard !Task.isCancelled else { return }
            await client.heartbeatIfNeeded()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        heartbeatTask?.cancel()
        let previous = preferenceTask
        preferenceTask = Task { [client] in
            await previous?.value
            await client.setEnabled(enabled)
        }
        if enabled { activityOpportunity() }
    }
}

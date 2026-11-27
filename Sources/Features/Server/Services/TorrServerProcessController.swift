import Darwin
import Foundation

enum TorrServerExecutablePath {
    static func resolve(saved: String, bundled: String?) -> String {
        guard let bundled else { return saved }
        let expanded = NSString(string: saved).expandingTildeInPath
        guard !expanded.isEmpty else {
            TorrServerLocalLog.shared.record(.executablePath, event: .bundled)
            return bundled
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let oldManagedSuffix = "/Library/Application Support/TorrServer Manager/\(torrServerExecutableName)"
        let bundledSuffix = "/Contents/Resources/\(torrServerExecutableName)"
        if url.path.hasSuffix(bundledSuffix) {
            let oldBundle = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let currentBundle = URL(fileURLWithPath: bundled).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            if url.path == bundled || Bundle(url: oldBundle)?.bundleIdentifier == Bundle(url: currentBundle)?.bundleIdentifier,
               Bundle(url: currentBundle)?.bundleIdentifier != nil {
                TorrServerLocalLog.shared.record(.executablePath, event: url.path == bundled ? .bundled : .bundlePathRelocated)
                return bundled
            }
        }
        var isDirectory: ObjCBool = false
        if url.path.hasSuffix(oldManagedSuffix)
            || !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) || isDirectory.boolValue {
            TorrServerLocalLog.shared.record(.executablePath, event: .savedUnavailable)
            return bundled
        }
        TorrServerLocalLog.shared.record(.executablePath, event: .saved)
        return url.path
    }
}

final class TorrServerProcessController {
    enum State {
        case stopped
        case running(pid: Int32)
        case external(TorrServerVersion)
        case stopping
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    private var task: Process?
    private var stopCompletions: [() -> Void] = []
    private var forceStopWorkItem: DispatchWorkItem?

    var isRunning: Bool {
        task?.isRunning == true
    }

    var runningPID: Int32? {
        guard let task, task.isRunning else { return nil }
        return task.processIdentifier
    }

    var isAvailable: Bool {
        isRunning || isExternal
    }

    var isExternal: Bool {
        if case .external = state { return true }
        return false
    }

    func attach(to version: TorrServerVersion) {
        guard !isRunning else { return }
        state = .external(version)
    }

    func detach() {
        if isExternal { state = .stopped }
    }

    // Check both loopback families without starting or stopping anyone else's process.
    static func isPortOccupied(_ port: UInt16 = 8090) -> Bool {
        for host in ["127.0.0.1", "::1"] {
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
            hints.ai_socktype = SOCK_STREAM
            var address: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, String(port), &hints, &address) == 0, let address else { continue }
            defer { freeaddrinfo(address) }
            let info = address.pointee
            let fd = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            guard bind(fd, info.ai_addr, info.ai_addrlen) == -1, errno == EADDRINUSE else { continue }
            // A closed connection can still reserve the address in TIME_WAIT.
            // SO_REUSEADDR would also mask live wildcard listeners on macOS.
            guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { return true }
            if connect(fd, info.ai_addr, info.ai_addrlen) == 0 { return true }
            if errno == ECONNREFUSED { continue }
            guard errno == EINPROGRESS else { return true }
            var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&event, 1, 100) > 0 else { return true }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return true }
            if error != ECONNREFUSED { return true }
        }
        return false
    }

    func start(executablePath: String) throws {
        guard !isAvailable else { return }
        do {
            if Self.isPortOccupied() {
                TorrServerLocalLog.shared.record(.portCheck, error: TorrServerBackendError.portOccupied, event: .portInUse)
                throw TorrServerBackendError.portOccupied
            }
            try launch(executablePath: executablePath)
        } catch {
            TorrServerLocalLog.shared.record(.processLaunch, error: error)
            state = .failed(error.localizedDescription)
            throw AppError("Не удалось запустить TorrServer: \(error.localizedDescription)")
        }
    }

    private func launch(executablePath: String) throws {
        let expandedPath = NSString(string: executablePath)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let executableURL = URL(fileURLWithPath: expandedPath).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: executableURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            TorrServerLocalLog.shared.record(.executablePath, error: CocoaError(.fileNoSuchFile))
            throw AppError("Файл TorrServer не найден. Выберите его заново.")
        }

        try makeExecutableIfNeeded(at: executableURL)

        let newTask = Process()
        newTask.executableURL = executableURL
        newTask.currentDirectoryURL = try serverDataDirectoryURL()
        let stdout = Pipe()
        let stderr = Pipe()
        newTask.standardOutput = stdout
        newTask.standardError = stderr
        TorrServerLocalLog.shared.capture(stdout, stage: .processStdout)
        TorrServerLocalLog.shared.capture(stderr, stage: .processStderr)
        newTask.terminationHandler = { [weak self] finishedTask in
            DispatchQueue.main.async {
                self?.handleTermination(finishedTask)
            }
        }

        do {
            try newTask.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        task = newTask
        TorrServerLocalLog.shared.record(.processLaunch, event: .started)
        state = .running(pid: newTask.processIdentifier)
    }

    func stop(completion: (() -> Void)? = nil) {
        if let completion {
            stopCompletions.append(completion)
        }

        guard let runningTask = task, runningTask.isRunning else {
            finishStopCompletions()
            if case .failed = state { return }
            state = .stopped
            return
        }

        state = .stopping
        runningTask.terminate()

        let pid = runningTask.processIdentifier
        let workItem = DispatchWorkItem { [weak self, weak runningTask] in
            guard let runningTask, runningTask.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, self.task === runningTask else { return }
                self.task = nil
                self.state = .stopped
                self.finishStopCompletions()
            }
        }
        forceStopWorkItem?.cancel()
        forceStopWorkItem = workItem
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func handleTermination(_ finishedTask: Process) {
        guard task === finishedTask else { return }

        forceStopWorkItem?.cancel()
        forceStopWorkItem = nil
        task = nil

        let wasStopping: Bool
        if case .stopping = state {
            wasStopping = true
        } else {
            wasStopping = false
        }

        if wasStopping || finishedTask.terminationStatus == 0 {
            TorrServerLocalLog.shared.record(.processExit, event: .stopped)
            state = .stopped
        } else {
            let error = NSError(domain: "TorrServe.Backend", code: Int(finishedTask.terminationStatus))
            TorrServerLocalLog.shared.record(.processExit, error: error)
            state = .failed("Процесс завершился с кодом \(finishedTask.terminationStatus)")
        }
        finishStopCompletions()
    }

    private func finishStopCompletions() {
        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func makeExecutableIfNeeded(at url: URL) throws {
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentMode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        let executableMode = currentMode | 0o111
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: executableMode)],
            ofItemAtPath: url.path
        )

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw AppError("macOS не разрешила сделать выбранный файл исполняемым.")
        }
    }

    private func serverDataDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppError("Не удалось найти папку Application Support.")
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("TorrServer Manager", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }
}

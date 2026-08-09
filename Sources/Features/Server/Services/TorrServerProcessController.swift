import Darwin
import Foundation

final class TorrServerProcessController {
    enum State {
        case stopped
        case running(pid: Int32)
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

    func start(executablePath: String) throws {
        guard !isRunning else { return }

        let expandedPath = NSString(string: executablePath)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let executableURL = URL(fileURLWithPath: expandedPath).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: executableURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw AppError("Файл TorrServer не найден. Выберите его заново.")
        }

        try makeExecutableIfNeeded(at: executableURL)

        let newTask = Process()
        newTask.executableURL = executableURL
        newTask.currentDirectoryURL = try serverDataDirectoryURL()
        newTask.standardOutput = FileHandle.nullDevice
        newTask.standardError = FileHandle.nullDevice
        newTask.terminationHandler = { [weak self] finishedTask in
            DispatchQueue.main.async {
                self?.handleTermination(finishedTask)
            }
        }

        do {
            try newTask.run()
            task = newTask
            state = .running(pid: newTask.processIdentifier)
        } catch {
            task = nil
            state = .failed(error.localizedDescription)
            throw AppError("Не удалось запустить TorrServer: \(error.localizedDescription)")
        }
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
            state = .stopped
        } else {
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

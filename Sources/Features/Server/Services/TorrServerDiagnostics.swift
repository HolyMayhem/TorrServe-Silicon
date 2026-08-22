import AppKit
import Foundation

final class TorrServerDiagnosticsService {
    private let api = NativeTorrServerAPI()

    func checkPort(language: AppLanguage) async -> DiagnosticResult {
        do {
            try await api.checkHealth()
            return DiagnosticResult(
                kind: .success,
                message: language == .russian
                    ? "Порт 8090 отвечает: API TorrServer доступен."
                    : "Port 8090 responds: TorrServer API is available."
            )
        } catch {
            return DiagnosticResult(
                kind: .failure,
                message: language == .russian
                    ? "Порт 8090 не отвечает. TorrServer может быть остановлен, ещё запускаться или порт занят другим процессом."
                    : "Port 8090 is not responding. TorrServer may be stopped, still starting, or the port may be used by another process."
            )
        }
    }

    func scanTorrServerProcesses(
        managedPID: Int32?,
        language: AppLanguage
    ) async -> TorrServerProcessScan {
        await Task.detached(priority: .userInitiated) {
            do {
                let rows = try Self.processRows()
                let listenerPIDs = Self.port8090ListenerPIDs()
                let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
                var matches: [DiagnosticProcessInfo] = []

                for row in rows {
                    guard row.pid != currentPID, row.pid != managedPID else { continue }

                    let executableName = row.executableName.lowercased()
                    let kind: DiagnosticProcessKind?
                    if executableName.hasPrefix("torrservermanag") {
                        kind = .application
                    } else if executableName.hasPrefix("torrserver") {
                        kind = .server
                    } else if listenerPIDs.contains(row.pid) {
                        kind = .portOwner
                    } else {
                        kind = nil
                    }

                    guard let kind else { continue }
                    matches.append(
                        DiagnosticProcessInfo(
                            pid: row.pid,
                            parentPID: row.parentPID,
                            executableName: row.executableName,
                            command: row.command,
                            kind: kind,
                            listensOnPort8090: listenerPIDs.contains(row.pid)
                        )
                    )
                }

                matches.sort {
                    if $0.kind == .application, $1.kind != .application { return true }
                    if $0.kind != .application, $1.kind == .application { return false }
                    return $0.pid < $1.pid
                }

                guard !matches.isEmpty else {
                    let portDescription: String
                    if let managedPID, listenerPIDs.contains(managedPID) {
                        portDescription = language == .russian
                            ? " Порт 8090 принадлежит текущему серверу (PID \(managedPID))."
                            : " Port 8090 belongs to this app's server (PID \(managedPID))."
                    } else if let owner = listenerPIDs.first {
                        portDescription = language == .russian
                            ? " Порт 8090 занят PID \(owner), но процесс уже недоступен для проверки."
                            : " Port 8090 is owned by PID \(owner), but the process is no longer available for inspection."
                    } else {
                        portDescription = ""
                    }

                    return TorrServerProcessScan(
                        result: DiagnosticResult(
                            kind: .success,
                            message: (language == .russian
                                ? "Внешних копий не найдено."
                                : "No external copies found.") + portDescription
                        ),
                        processes: [],
                        listenerPIDs: listenerPIDs
                    )
                }

                let summary = matches.map { process in
                    let port = process.listensOnPort8090 ? " · :8090" : ""
                    return "\(process.kind.title(language: language)) PID \(process.pid)\(port)"
                }.joined(separator: "; ")

                return TorrServerProcessScan(
                    result: DiagnosticResult(
                        kind: .warning,
                        message: (language == .russian
                            ? "Найдены внешние процессы: "
                            : "External processes found: ") + summary
                    ),
                    processes: matches,
                    listenerPIDs: listenerPIDs
                )
            } catch {
                return TorrServerProcessScan(
                    result: DiagnosticResult(
                        kind: .failure,
                        message: language == .russian
                            ? "Не удалось получить список процессов TorrServer."
                            : "Could not inspect TorrServer processes."
                    ),
                    processes: [],
                    listenerPIDs: []
                )
            }
        }.value
    }

    func stopAllDetectedProcesses(
        alreadyStoppedCount: Int,
        language: AppLanguage
    ) async -> DiagnosticResult {
        let verified = await scanTorrServerProcesses(
            managedPID: nil,
            language: language
        )
        let safeProcesses = verified.processes

        guard !safeProcesses.isEmpty else {
            return DiagnosticResult(
                kind: .success,
                message: language == .russian
                    ? (alreadyStoppedCount > 0
                        ? "Все экземпляры остановлены: \(alreadyStoppedCount)."
                        : "Запущенных экземпляров TorrServer не найдено.")
                    : (alreadyStoppedCount > 0
                        ? "All instances stopped: \(alreadyStoppedCount)."
                        : "No running TorrServer instances found.")
            )
        }

        await Task.detached(priority: .userInitiated) {
            for process in safeProcesses {
                Darwin.kill(process.pid, SIGTERM)
            }
        }.value

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let remaining = await scanTorrServerProcesses(
            managedPID: nil,
            language: language
        )
        let remainingPIDs = Set(remaining.processes.map(\.pid))

        if !remainingPIDs.isEmpty {
            await Task.detached(priority: .userInitiated) {
                for pid in remainingPIDs {
                    Darwin.kill(pid, SIGKILL)
                }
            }.value
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        let finalScan = await scanTorrServerProcesses(
            managedPID: nil,
            language: language
        )
        let failedPIDs = Set(finalScan.processes.map(\.pid))

        guard failedPIDs.isEmpty else {
            return DiagnosticResult(
                kind: .failure,
                message: language == .russian
                    ? "Не удалось остановить PID: \(failedPIDs.sorted().map(String.init).joined(separator: ", "))."
                    : "Could not stop PID: \(failedPIDs.sorted().map(String.init).joined(separator: ", "))."
            )
        }

        let stoppedCount = Set(safeProcesses.map(\.pid))
            .union(remainingPIDs)
            .count + alreadyStoppedCount
        return DiagnosticResult(
            kind: .success,
            message: language == .russian
                ? "Все экземпляры остановлены: \(stoppedCount). Порт 8090 освобождён."
                : "All instances stopped: \(stoppedCount). Port 8090 is free."
        )
    }

    func inspectExecutable(path: String, language: AppLanguage) async -> DiagnosticResult {
        await Task.detached(priority: .userInitiated) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return DiagnosticResult(
                    kind: .failure,
                    message: language == .russian
                        ? "Исполняемый файл не выбран."
                        : "No executable selected."
                )
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return DiagnosticResult(
                    kind: .failure,
                    message: language == .russian
                        ? "Выбранный файл не существует."
                        : "The selected file does not exist."
                )
            }
            guard FileManager.default.isExecutableFile(atPath: trimmed) else {
                return DiagnosticResult(
                    kind: .failure,
                    message: language == .russian
                        ? "Файл не является исполняемым. Разрешите запуск или выберите другую сборку."
                        : "The file is not executable. Allow execution or select another build."
                )
            }
            do {
                let type = try Self.run("/usr/bin/file", arguments: [trimmed])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isNative = type.localizedCaseInsensitiveContains("arm64")
                return DiagnosticResult(
                    kind: isNative ? .success : .warning,
                    message: isNative
                        ? (language == .russian
                            ? "Файл исправен и содержит код Apple Silicon arm64."
                            : "Executable is valid and contains Apple Silicon arm64 code.")
                        : (language == .russian
                            ? "Файл запускаемый, но arm64 не обнаружен: \(type)"
                            : "Executable can run, but arm64 was not detected: \(type)")
                )
            } catch {
                return DiagnosticResult(
                    kind: .warning,
                    message: language == .russian
                        ? "Файл найден, но определить его архитектуру не удалось."
                        : "The executable was found, but its architecture could not be determined."
                )
            }
        }.value
    }

    func storageSnapshot(torrents: [NativeTorrent]) async -> TorrServerStorageSnapshot {
        var snapshot = TorrServerStorageSnapshot()
        let home = NSHomeDirectory()
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: home),
           let free = attributes[.systemFreeSize] as? NSNumber {
            snapshot.freeDiskSpace = free.int64Value
        }

        if let settings = try? await api.settings() {
            snapshot.cacheCapacity = settings.cacheSize
            snapshot.diskCacheEnabled = settings.useDisk
            snapshot.diskCachePath = settings.torrentsSavePath
            if settings.useDisk, Self.isSafeCacheRoot(settings.torrentsSavePath) {
                snapshot.diskCacheSize = await Task.detached {
                    Self.directorySize(atPath: settings.torrentsSavePath)
                }.value
            }
        }

        for torrent in torrents where torrent.isActive {
            if let state = try? await api.cacheState(hash: torrent.hash) {
                snapshot.cacheUsed += state.filled
                snapshot.cacheCapacity = max(snapshot.cacheCapacity, state.capacity)
            }
        }
        return snapshot
    }

    func clearCache(torrents: [NativeTorrent]) async throws {
        let settings = try? await api.settings()
        for torrent in torrents where !torrent.hash.isEmpty {
            try? await api.dropTorrentCache(hash: torrent.hash)
        }

        guard let settings,
              settings.useDisk,
              Self.isSafeCacheRoot(settings.torrentsSavePath) else { return }

        let root = URL(fileURLWithPath: settings.torrentsSavePath, isDirectory: true)
            .standardizedFileURL
        let knownHashes = Set(torrents.map { $0.hash.lowercased() }.filter { $0.count == 40 })
        for hash in knownHashes {
            let target = root.appendingPathComponent(hash, isDirectory: true).standardizedFileURL
            guard target.deletingLastPathComponent() == root else { continue }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    func report(
        status: String,
        tooltip: String,
        executablePath: String,
        storage: TorrServerStorageSnapshot,
        port: DiagnosticResult,
        processScan: TorrServerProcessScan,
        executable: DiagnosticResult
    ) -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "unknown"
        return [
            "TorrServer GUI diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "App: \(appVersion)",
            "App PID: \(ProcessInfo.processInfo.processIdentifier)",
            "Status: \(status)",
            "Details: \(tooltip)",
            "Executable: \(executablePath)",
            "Port: \(port.message)",
            "Processes: \(processScan.result.message)",
            "Port 8090 listeners: \(processScan.listenerPIDs.map(String.init).joined(separator: ", "))",
            "External process details:",
            processScan.processes.isEmpty
                ? "- none"
                : processScan.processes.map {
                    "- PID \($0.pid), PPID \($0.parentPID), executable \($0.executableName), kind \($0.kind), port8090 \($0.listensOnPort8090), command \($0.command)"
                }.joined(separator: "\n"),
            "Executable check: \(executable.message)",
            "Memory buffer: \(storage.cacheUsed) / \(storage.cacheCapacity) bytes",
            "Disk cache: \(storage.diskCacheSize) bytes at \(storage.diskCachePath)",
            "Free disk: \(storage.freeDiskSpace) bytes"
        ].joined(separator: "\n")
    }

    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw AppError(output.isEmpty ? "Diagnostic command failed." : output)
        }
        return output
    }

    private struct ProcessRow {
        let pid: Int32
        let parentPID: Int32
        let executableName: String
        let command: String
    }

    private static func processRows() throws -> [ProcessRow] {
        let output = try run(
            "/bin/ps",
            arguments: ["-U", NSUserName(), "-o", "pid=,ppid=,ucomm=,command="]
        )
        return output.split(separator: "\n").compactMap { line in
            let components = line.split(
                maxSplits: 3,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            )
            guard components.count == 4,
                  let pid = Int32(components[0]),
                  let parentPID = Int32(components[1]) else { return nil }
            return ProcessRow(
                pid: pid,
                parentPID: parentPID,
                executableName: String(components[2]),
                command: String(components[3])
            )
        }
    }

    private static func port8090ListenerPIDs() -> [Int32] {
        let output = (try? run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-Fp", "-iTCP:8090", "-sTCP:LISTEN"]
        )) ?? ""
        return output.split(separator: "\n").compactMap { line in
            guard line.first == "p" else { return nil }
            return Int32(line.dropFirst())
        }
    }

    private static func isSafeCacheRoot(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return !normalized.isEmpty
            && normalized != "/"
            && normalized != NSHomeDirectory()
            && normalized.count > 4
    }

    private static func directorySize(atPath path: String) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

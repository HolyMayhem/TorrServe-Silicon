import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppDelegate {
    func refreshPlayerAvailability() {
        libraryModel.refreshDetectedPlayers()
        mainWindowModel.detectedPlayers = libraryModel.detectedPlayers
        mainWindowModel.preferredPlayer = libraryModel.playerChoice
    }

    func refreshStorage() {
        guard !mainWindowModel.isRefreshingStorage else { return }
        mainWindowModel.isRefreshingStorage = true
        let torrents = libraryModel.torrents
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.diagnosticsService.storageSnapshot(torrents: torrents)
            self.mainWindowModel.storage = snapshot
            self.mainWindowModel.isRefreshingStorage = false
        }
    }

    func clearTorrServerCache() {
        guard !mainWindowModel.isClearingCache else { return }
        mainWindowModel.isClearingCache = true
        let torrents = libraryModel.torrents
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.diagnosticsService.clearCache(torrents: torrents)
                self.libraryModel.refresh()
            } catch {
                self.showAlert(title: "TorrServer", message: error.localizedDescription)
            }
            self.mainWindowModel.isClearingCache = false
            self.refreshStorage()
        }
    }

    func checkTorrServerPort() {
        let revision = diagnosticsRevision
        let language = currentLanguage
        mainWindowModel.portDiagnostic = DiagnosticResult(
            kind: .checking,
            message: ""
        )
        mainWindowModel.latestDiagnostic = mainWindowModel.portDiagnostic
        Task { [weak self] in
            guard let self else { return }
            let result = await self.diagnosticsService.checkPort(language: language)
            guard revision == self.diagnosticsRevision else { return }
            self.mainWindowModel.portDiagnostic = result
            self.mainWindowModel.latestDiagnostic = self.mainWindowModel.portDiagnostic
        }
    }

    func findOtherTorrServerProcesses() {
        let revision = diagnosticsRevision
        let language = currentLanguage
        mainWindowModel.processDiagnostic = DiagnosticResult(
            kind: .checking,
            message: ""
        )
        mainWindowModel.latestDiagnostic = mainWindowModel.processDiagnostic
        Task { [weak self] in
            guard let self else { return }
            let scan = await self.diagnosticsService.scanTorrServerProcesses(
                managedPID: self.processController.runningPID,
                language: language
            )
            guard revision == self.diagnosticsRevision else { return }
            self.mainWindowModel.processScan = scan
            self.mainWindowModel.processDiagnostic = scan.result
            self.mainWindowModel.latestDiagnostic = scan.result
        }
    }

    func runFullDiagnostics() {
        guard !mainWindowModel.isRunningDiagnostics else { return }
        let revision = diagnosticsRevision
        Task { [weak self] in
            await self?.performFullDiagnostics(revision: revision)
        }
    }

    func performFullDiagnostics(revision: Int? = nil) async {
        let revision = revision ?? diagnosticsRevision
        guard revision == diagnosticsRevision,
              !mainWindowModel.isRunningDiagnostics else { return }

        mainWindowModel.isRunningDiagnostics = true
        let checking = DiagnosticResult(kind: .checking, message: "")
        mainWindowModel.portDiagnostic = checking
        mainWindowModel.processDiagnostic = checking
        mainWindowModel.executableDiagnostic = checking
        mainWindowModel.latestDiagnostic = checking

        let language = currentLanguage
        let path = executablePath
        let managedPID = processController.runningPID
        let torrents = libraryModel.torrents

        async let port = diagnosticsService.checkPort(language: language)
        async let processScan = diagnosticsService.scanTorrServerProcesses(
            managedPID: managedPID,
            language: language
        )
        async let executable = diagnosticsService.inspectExecutable(
            path: path,
            language: language
        )
        async let storage = diagnosticsService.storageSnapshot(torrents: torrents)

        let results = await (port, processScan, executable, storage)
        guard revision == diagnosticsRevision else { return }
        mainWindowModel.portDiagnostic = results.0
        mainWindowModel.processScan = results.1
        mainWindowModel.processDiagnostic = results.1.result
        mainWindowModel.executableDiagnostic = results.2
        mainWindowModel.storage = results.3
        mainWindowModel.latestDiagnostic = fullDiagnosticSummary(
            port: results.0,
            process: results.1.result,
            executable: results.2,
            language: language
        )
        mainWindowModel.isRunningDiagnostics = false
    }

    func fullDiagnosticSummary(
        port: DiagnosticResult,
        process: DiagnosticResult,
        executable: DiagnosticResult,
        language: AppLanguage
    ) -> DiagnosticResult {
        let checks = [port, process, executable]
        let failures = checks.filter { $0.kind == .failure }
        let warnings = checks.filter { $0.kind == .warning }

        if failures.isEmpty, warnings.isEmpty {
            return DiagnosticResult(
                kind: .success,
                message: language == .russian
                    ? "Проверка завершена: порт, процессы и исполняемый файл в порядке."
                    : "Check completed: port, processes, and executable are healthy."
            )
        }

        let details = (failures + warnings)
            .map(\.message)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return DiagnosticResult(
            kind: failures.isEmpty ? .warning : .failure,
            message: (language == .russian
                ? "Проверка обнаружила проблему. "
                : "The check found an issue. ") + details
        )
    }

    func stopExternalTorrServerProcesses() {
        guard !mainWindowModel.isStoppingExternalProcesses else { return }
        let revision = diagnosticsRevision
        let language = currentLanguage
        mainWindowModel.isStoppingExternalProcesses = true
        mainWindowModel.latestDiagnostic = DiagnosticResult(
            kind: .checking,
            message: ""
        )

        Task { [weak self] in
            guard let self else { return }
            let stoppedManagedServer = await self.stopManagedTorrServerIfNeeded()
            let result = await self.diagnosticsService.stopAllDetectedProcesses(
                alreadyStoppedCount: stoppedManagedServer ? 1 : 0,
                language: language
            )
            let refreshedScan = await self.diagnosticsService.scanTorrServerProcesses(
                managedPID: nil,
                language: language
            )
            guard revision == self.diagnosticsRevision else { return }
            self.mainWindowModel.processScan = refreshedScan
            self.mainWindowModel.processDiagnostic = refreshedScan.result
            self.mainWindowModel.latestDiagnostic = result
            self.mainWindowModel.isStoppingExternalProcesses = false
        }
    }

    private func stopManagedTorrServerIfNeeded() async -> Bool {
        guard processController.isRunning else { return false }

        await withCheckedContinuation { continuation in
            processController.stop {
                continuation.resume()
            }
        }
        return true
    }

    func checkTorrServerExecutable() {
        let revision = diagnosticsRevision
        let language = currentLanguage
        mainWindowModel.executableDiagnostic = DiagnosticResult(
            kind: .checking,
            message: ""
        )
        mainWindowModel.latestDiagnostic = mainWindowModel.executableDiagnostic
        let path = executablePath
        Task { [weak self] in
            guard let self else { return }
            let result = await self.diagnosticsService.inspectExecutable(
                path: path,
                language: language
            )
            guard revision == self.diagnosticsRevision else { return }
            self.mainWindowModel.executableDiagnostic = result
            self.mainWindowModel.latestDiagnostic = result
        }
    }

    func diagnosticReport() -> String {
        diagnosticsService.report(
            status: mainWindowModel.statusText,
            tooltip: mainWindowModel.statusTooltip,
            executablePath: executablePath,
            storage: mainWindowModel.storage,
            port: mainWindowModel.portDiagnostic,
            processScan: mainWindowModel.processScan,
            executable: mainWindowModel.executableDiagnostic
        )
    }

    var diagnosticsHaveNotRun: Bool {
        mainWindowModel.portDiagnostic.kind == .idle
            || mainWindowModel.processDiagnostic.kind == .idle
            || mainWindowModel.executableDiagnostic.kind == .idle
    }

    func copyDiagnosticReport() {
        Task { [weak self] in
            guard let self else { return }
            if self.diagnosticsHaveNotRun {
                await self.performFullDiagnostics()
            }

            let report = self.diagnosticReport()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(report, forType: .string)
            let didVerify = pasteboard.string(forType: .string) == report
            self.mainWindowModel.latestDiagnostic = DiagnosticResult(
                kind: didWrite && didVerify ? .success : .failure,
                message: didWrite && didVerify
                    ? (self.currentLanguage == .russian
                        ? "Отчёт скопирован в буфер обмена."
                        : "The report was copied to the clipboard.")
                    : (self.currentLanguage == .russian
                        ? "Не удалось записать отчёт в буфер обмена."
                        : "Could not write the report to the clipboard.")
            )
        }
    }

    func saveDiagnosticReport() {
        Task { [weak self] in
            guard let self else { return }
            if self.diagnosticsHaveNotRun {
                await self.performFullDiagnostics()
            }

            let panel = NSSavePanel()
            panel.title = self.currentLanguage == .russian
                ? "Сохранить отчёт диагностики"
                : "Save diagnostic report"
            panel.nameFieldStringValue = "TorrServer-Diagnostics.txt"
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try self.diagnosticReport().write(to: url, atomically: true, encoding: .utf8)
                self.mainWindowModel.latestDiagnostic = DiagnosticResult(
                    kind: .success,
                    message: self.currentLanguage == .russian
                        ? "Отчёт сохранён: \(url.lastPathComponent)."
                        : "Report saved: \(url.lastPathComponent)."
                )
            } catch {
                self.mainWindowModel.latestDiagnostic = DiagnosticResult(
                    kind: .failure,
                    message: self.currentLanguage == .russian
                        ? "Не удалось сохранить отчёт диагностики."
                        : "Could not save the diagnostic report."
                )
            }
        }
    }
}

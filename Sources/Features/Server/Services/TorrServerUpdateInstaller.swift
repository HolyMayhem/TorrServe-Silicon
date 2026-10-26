import Foundation

/// Activates a downloaded executable while retaining the previous selection for rollback.
@MainActor
struct TorrServerUpdateInstaller {
    let stop: () async -> Void
    let start: (String) throws -> Int32
    let isRunning: (Int32) -> Bool
    let checkHealth: () async throws -> Void
    var readinessTimeout: TimeInterval = 12

    func install(
        executablePath: String,
        previousPath: String,
        restartingServer: Bool,
        selectPath: (String) -> Void
    ) async throws {
        guard restartingServer else {
            selectPath(executablePath)
            return
        }

        await stop()
        selectPath(executablePath)
        do {
            let pid = try start(executablePath)
            try await waitForReadiness(pid: pid)
        } catch {
            let updateError = error
            await stop()
            selectPath(previousPath)
            do {
                let previousPID = try start(previousPath)
                try await waitForReadiness(pid: previousPID)
            } catch {
                throw AppError("Выбранная версия TorrServer не запустилась: \(updateError.localizedDescription) Предыдущая версия сохранена, но её запуск также не удался: \(error.localizedDescription)")
            }
            throw AppError("Выбранная версия TorrServer не запустилась: \(updateError.localizedDescription) Работа предыдущей версии восстановлена.")
        }
    }

    private func waitForReadiness(pid: Int32) async throws {
        let deadline = Date().addingTimeInterval(readinessTimeout)
        repeat {
            guard isRunning(pid) else { throw AppError("Процесс TorrServer завершился во время запуска.") }
            do {
                try await checkHealth()
                guard isRunning(pid) else { throw AppError("Процесс TorrServer завершился во время запуска.") }
                return
            } catch {
                if Date() >= deadline { break }
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline
        throw AppError("TorrServer не ответил после запуска.")
    }
}

import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdateController: NSObject, NSMenuItemValidation {
    let updaterController: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    var updater: SPUUpdater {
        updaterController.updater
    }

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func start() {
        updaterController.startUpdater()
    }

    func bind(to model: MainWindowModel) {
        cancellables.removeAll()

        updater.publisher(
            for: \.automaticallyChecksForUpdates,
            options: [.initial, .new]
        )
        .receive(on: RunLoop.main)
        .sink { [weak model] enabled in
            model?.automaticallyChecksForAppUpdates = enabled
        }
        .store(in: &cancellables)

        updater.publisher(
            for: \.automaticallyDownloadsUpdates,
            options: [.initial, .new]
        )
        .receive(on: RunLoop.main)
        .sink { [weak model] enabled in
            model?.automaticallyDownloadsAppUpdates = enabled
        }
        .store(in: &cancellables)

        updater.publisher(
            for: \.canCheckForUpdates,
            options: [.initial, .new]
        )
        .receive(on: RunLoop.main)
        .sink { [weak model] canCheck in
            model?.canCheckForAppUpdates = canCheck
        }
        .store(in: &cancellables)

        model.onAutomaticallyChecksForAppUpdatesChanged = { [weak self] enabled in
            self?.updater.automaticallyChecksForUpdates = enabled
        }
        model.onAutomaticallyDownloadsAppUpdatesChanged = { [weak self] enabled in
            self?.updater.automaticallyDownloadsUpdates = enabled
        }
        model.onCheckForAppUpdates = { [weak self] in
            self?.updater.checkForUpdates()
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return updater.canCheckForUpdates
    }
}

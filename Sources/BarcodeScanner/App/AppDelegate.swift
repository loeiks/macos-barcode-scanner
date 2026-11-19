import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: ScannerAppModel?
    private var statusController: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings()
        let model = ScannerAppModel(settings: settings)
        self.model = model
        statusController = StatusItemController(model: model)

        observeEnvironment(for: model)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func observeEnvironment(for model: ScannerAppModel) {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak model] _ in
                model?.systemWillSleep()
            }
        )
        observers.append(
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak model] _ in
                model?.systemDidWake()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak model] _ in
                model?.applicationDidBecomeActive()
            }
        )
    }
}

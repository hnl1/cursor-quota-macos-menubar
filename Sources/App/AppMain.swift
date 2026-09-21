import AppKit

@main
enum CursorQuotaApp {
    static func main() {
        if CommandLine.arguments.contains("--refresh") {
            DistributedNotificationCenter.default().post(
                name: AppConfig.refreshNotification,
                object: nil
            )
            return
        }
        if CommandLine.arguments.contains("--nudge") {
            DistributedNotificationCenter.default().post(
                name: AppConfig.hookNotification,
                object: nil
            )
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Retain.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.run()
    }
}

@MainActor
private enum Retain {
    nonisolated(unsafe) static var delegate: AppDelegate?
}

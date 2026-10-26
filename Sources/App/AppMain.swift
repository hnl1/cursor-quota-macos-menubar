import AppKit

@main
enum CursorQuotaApp {
    static func main() {
        if CommandLine.arguments.contains("--refresh") {
            Log.app.info("post refresh request")
            DistributedNotificationCenter.default().post(
                name: AppConfig.refreshNotification,
                object: nil
            )
            return
        }
        if CommandLine.arguments.contains("--nudge") {
            Log.app.info("post hook nudge")
            DistributedNotificationCenter.default().post(
                name: AppConfig.hookNotification,
                object: nil
            )
            return
        }
        Log.app.notice("launch menu bar app")

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Retain.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
private enum Retain {
    nonisolated(unsafe) static var delegate: AppDelegate?
}

import AppKit

@main
enum CursorQuotaApp {
    static func main() {
        if CommandLine.arguments.contains("--refresh") {
            ProbeLog.write("process --refresh")
            DistributedNotificationCenter.default().post(
                name: AppConfig.refreshNotification,
                object: nil
            )
            return
        }
        if CommandLine.arguments.contains("--nudge") {
            ProbeLog.write("process --nudge")
            DistributedNotificationCenter.default().post(
                name: AppConfig.hookNotification,
                object: nil
            )
            return
        }
        ProbeLog.write("process gui")

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

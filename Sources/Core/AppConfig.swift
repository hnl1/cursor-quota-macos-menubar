import CoreGraphics
import Foundation

enum AppConfig {
    static let appName = "Cursor 额度"
    static let bundleName = "Cursor Quota"
    static let popoverTitle = "CURSOR 额度"
    static let popoverWidth: CGFloat = 308
    static let refreshInterval: TimeInterval = 5 * 60
    static let clockInterval: TimeInterval = 60
    static let hookRefreshDelay: TimeInterval = 3
    static let refreshNotification = Notification.Name("com.hnl1.cursorquota.refresh")
    static let hookNotification = Notification.Name("com.hnl1.cursorquota.nudge")
    static let requestTimeout: TimeInterval = 12
    static let maxResponseBytes = 1_048_576
    static let criticalRemaining = 0.15
    static let allowedHost = "api2.cursor.sh"

    static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!
    static let planURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
    )!
    static let grokBotURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"
    )!

    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == allowedHost
            && (url.port == nil || url.port == 443)
    }
}

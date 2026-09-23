import Foundation
import ServiceManagement

/// 开机自启。优先登记为系统登录项；签名不被接受时，改在用户 LaunchAgents 里写一份。
@MainActor
enum LoginItem {
    enum Change: Equatable {
        case enabled
        case disabled
        case needsApproval
        case failed
    }

    private static let intentKey = "login.opensAtLogin"
    private static let agentLabel = "com.hnl1.cursorquota"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist")
    }

    /// 下次登录会不会真的打开。系统还没批准时不算。
    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// 没选过时默认开机自启。选过之后按用户的选择恢复；重装后签名变化导致登录项失效时，再登记一次。
    static func restoreIfNeeded() {
        guard UserDefaults.standard.object(forKey: intentKey) != nil else {
            _ = setEnabled(true)
            return
        }
        guard UserDefaults.standard.bool(forKey: intentKey) else { return }
        if isEnabled { return }
        if SMAppService.mainApp.status == .requiresApproval { return }
        _ = setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) -> Change {
        if !enabled {
            UserDefaults.standard.set(false, forKey: intentKey)
            disableService()
            removeAgent()
            return .disabled
        }

        UserDefaults.standard.set(true, forKey: intentKey)
        switch enableService() {
        case .enabled:
            removeAgent()
            return .enabled
        case .needsApproval:
            return .needsApproval
        case .failed:
            return writeAgent() ? .enabled : .failed
        }
    }

    private enum ServiceResult {
        case enabled
        case needsApproval
        case failed
    }

    private static func enableService() -> ServiceResult {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
        do {
            try service.register()
        } catch {
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .needsApproval
            case .notRegistered, .notFound:
                return .failed
            @unknown default:
                return .failed
            }
        }
        return service.status == .requiresApproval ? .needsApproval : .enabled
    }

    private static func disableService() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled, .requiresApproval:
            try? service.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
    }

    private static func writeAgent() -> Bool {
        let appPath = Bundle.main.bundleURL.path
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", appPath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: agentURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func removeAgent() {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return }
        try? FileManager.default.removeItem(at: agentURL)
    }
}

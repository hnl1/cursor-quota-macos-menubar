import Foundation

enum QuotaError: LocalizedError, Equatable, Sendable {
    case cursorNotOpened
    case notSignedIn
    case databaseBusy
    case loginExpired
    case usageDisabled
    case unexpectedPayload
    case timedOut
    case offline
    case rateLimited
    case server

    var errorDescription: String? {
        switch self {
        case .cursorNotOpened:
            "还没有找到 Cursor 本地数据。请先安装并打开 Cursor。"
        case .notSignedIn:
            "请先在 Cursor 里登录，再查看用量。"
        case .databaseBusy:
            "正在读取 Cursor 登录信息，请稍后再试。"
        case .loginExpired:
            "Cursor 登录已过期，请打开 Cursor 重新登录。"
        case .usageDisabled:
            "这个账号当前没有可用的用量数据。"
        case .unexpectedPayload:
            "Cursor 返回了无法识别的用量格式。"
        case .timedOut:
            "Cursor 用量接口超时。"
        case .offline:
            "无法连接到 Cursor。"
        case .rateLimited:
            "用量查询过于频繁，请稍后再试。"
        case .server:
            "Cursor 用量服务暂时不可用。"
        }
    }

    var keepsLastReading: Bool {
        switch self {
        case .cursorNotOpened, .notSignedIn, .loginExpired, .usageDisabled:
            false
        case .databaseBusy, .unexpectedPayload, .timedOut, .offline, .rateLimited, .server:
            true
        }
    }
}

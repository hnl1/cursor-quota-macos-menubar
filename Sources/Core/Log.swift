import OSLog

/// 查看：log stream --predicate 'subsystem == "com.hnl1.cursorquota"' --info
/// 动态字符串默认会被系统隐去，只对不含令牌和口令的值标 .public。
enum Log {
    private static let subsystem = "com.hnl1.cursorquota"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let network = Logger(subsystem: subsystem, category: "network")
}

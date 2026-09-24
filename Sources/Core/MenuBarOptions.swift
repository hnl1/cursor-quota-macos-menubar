import Foundation

/// 菜单栏上的全局显示开关。和每条额度的勾选分开存。
struct MenuBarOptions: Sendable, Equatable {
    var showsPercent: Bool
    /// 真：圆环和百分比按已用画。假：按剩余画。
    var showsUsed: Bool
    /// 假：节奏色换成系统文字色。过期和出错的橙色提醒不受影响。
    var showsColor: Bool = true

    static let `default` = MenuBarOptions(showsPercent: false, showsUsed: true, showsColor: true)

    private static let percentKey = "menubar.showsPercent"
    private static let usedKey = "menubar.showsUsed"
    private static let colorKey = "menubar.showsColor"

    static func load(from defaults: UserDefaults) -> MenuBarOptions {
        MenuBarOptions(
            showsPercent: stored(defaults, percentKey, default: false),
            showsUsed: stored(defaults, usedKey, default: true),
            showsColor: stored(defaults, colorKey, default: true)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showsPercent, forKey: Self.percentKey)
        defaults.set(showsUsed, forKey: Self.usedKey)
        defaults.set(showsColor, forKey: Self.colorKey)
    }

    private static func stored(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

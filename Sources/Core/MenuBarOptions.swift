import Foundation

/// 菜单栏上的全局显示开关。和每条额度的勾选分开存。
struct MenuBarOptions: Sendable, Equatable {
    var showsPercent: Bool

    static let `default` = MenuBarOptions(showsPercent: true)

    private static let percentKey = "menubar.showsPercent"

    static func load(from defaults: UserDefaults) -> MenuBarOptions {
        guard defaults.object(forKey: percentKey) != nil else { return .default }
        return MenuBarOptions(showsPercent: defaults.bool(forKey: percentKey))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showsPercent, forKey: Self.percentKey)
    }
}

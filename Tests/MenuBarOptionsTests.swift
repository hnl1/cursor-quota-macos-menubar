import Foundation

enum MenuBarOptionsTests {
    static func run() -> Int {
        var failures = 0
        failures += defaultsToShowingPercent()
        failures += roundTripsHiddenPercent()
        return failures
    }

    private static func defaultsToShowingPercent() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults) == .default,
            "没存过时应默认在菜单栏显示百分比"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }

    private static func roundTripsHiddenPercent() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let hidden = MenuBarOptions(showsPercent: false)
        hidden.save(to: defaults)
        var failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults) == hidden,
            "关闭百分比后应能读回，实际 \(MenuBarOptions.load(from: defaults))"
        )
        MenuBarOptions.default.save(to: defaults)
        failures += TestSupport.expect(
            MenuBarOptions.load(from: defaults).showsPercent,
            "重新打开后应读回显示百分比"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }
}

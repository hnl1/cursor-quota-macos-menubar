import Foundation

enum MenuBarOptionsTests {
    static func run() -> Int {
        var failures = 0
        failures += defaultsToShowingPercent()
        failures += roundTripsHiddenPercent()
        failures += defaultsToShowingUsed()
        failures += roundTripsRemaining()
        failures += defaultsToShowingColor()
        failures += roundTripsHiddenColor()
        return failures
    }

    private static func defaultsToShowingPercent() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let loaded = MenuBarOptions.load(from: defaults)
        let failures = TestSupport.expect(
            loaded == .default && loaded.showsPercent == false,
            "没存过时菜单栏百分比应默认关闭"
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
        let shown = MenuBarOptions(showsPercent: true, showsUsed: true)
        shown.save(to: defaults)
        var failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults) == shown,
            "打开百分比后应能读回，实际 \(MenuBarOptions.load(from: defaults))"
        )
        MenuBarOptions.default.save(to: defaults)
        failures += TestSupport.expect(
            MenuBarOptions.load(from: defaults).showsPercent == false,
            "回到默认后菜单栏百分比应关闭"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }

    private static func defaultsToShowingUsed() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar.used"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "menubar.showsPercent")
        let failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults).showsUsed,
            "没存过展示方向时应默认展示已用"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }

    private static func roundTripsRemaining() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar.used"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let remaining = MenuBarOptions(showsPercent: true, showsUsed: false)
        remaining.save(to: defaults)
        let failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults) == remaining,
            "切到展示剩余后应能读回，实际 \(MenuBarOptions.load(from: defaults))"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }

    private static func defaultsToShowingColor() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar.color"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "menubar.showsPercent")
        defaults.set(false, forKey: "menubar.showsUsed")
        let failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults).showsColor,
            "没存过颜色开关时应默认显示颜色"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }

    private static func roundTripsHiddenColor() -> Int {
        let suite = "com.hnl1.cursorquota.tests.menubar.color"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let plain = MenuBarOptions(showsPercent: false, showsUsed: true, showsColor: false)
        plain.save(to: defaults)
        let failures = TestSupport.expect(
            MenuBarOptions.load(from: defaults) == plain,
            "关掉颜色后应能读回，实际 \(MenuBarOptions.load(from: defaults))"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }
}

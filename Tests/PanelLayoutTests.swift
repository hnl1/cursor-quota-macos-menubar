import Foundation

enum PanelLayoutTests {
    static func run() -> Int {
        var failures = 0
        failures += defaultsToThirdPartyOnly()
        failures += fillsMissingKinds()
        failures += keepsAtLeastOneVisible()
        failures += movesWithinBounds()
        failures += roundTripsThroughDefaults()
        return failures
    }

    private static func defaultsToThirdPartyOnly() -> Int {
        let layout = PanelLayout.default
        var failures = TestSupport.expect(
            layout.visible == [.apiModels],
            "默认应只勾选其他模型，实际 \(layout.visible)"
        )
        failures += TestSupport.expect(
            layout.order == PoolKind.allCases,
            "默认顺序应保持声明顺序，实际 \(layout.order)"
        )
        return failures
    }

    private static func fillsMissingKinds() -> Int {
        let layout = PanelLayout(order: [.grokBot, .grokBot], hidden: [])
        var failures = TestSupport.expect(
            layout.order.count == PoolKind.allCases.count,
            "顺序里应补齐缺失的额度，实际 \(layout.order)"
        )
        failures += TestSupport.expect(
            layout.order.first == .grokBot,
            "已保存的顺序应保留在前，实际 \(layout.order)"
        )
        return failures
    }

    private static func keepsAtLeastOneVisible() -> Int {
        var layout = PanelLayout(order: PoolKind.allCases, hidden: [])
        layout.setVisible(false, for: .apiModels)
        layout.setVisible(false, for: .grokBot)
        var failures = TestSupport.expect(
            layout.visible == [.cursorModels],
            "隐藏两项后应只剩 Cursor 模型，实际 \(layout.visible)"
        )
        layout.setVisible(false, for: .cursorModels)
        failures += TestSupport.expect(
            layout.visible == [.cursorModels],
            "最后一项不允许隐藏，实际 \(layout.visible)"
        )
        failures += TestSupport.expect(
            PanelLayout(order: PoolKind.allCases, hidden: Set(PoolKind.allCases)).visible
                == [.apiModels],
            "全部隐藏的存档应回退为默认，只留其他模型"
        )
        return failures
    }

    private static func movesWithinBounds() -> Int {
        var layout = PanelLayout.default
        layout.move(.grokBot, by: -1)
        var failures = TestSupport.expect(
            layout.order == [.cursorModels, .grokBot, .apiModels],
            "上移应与前一项交换，实际 \(layout.order)"
        )
        layout.move(.cursorModels, by: -1)
        failures += TestSupport.expect(
            layout.order == [.cursorModels, .grokBot, .apiModels],
            "首项上移应无变化，实际 \(layout.order)"
        )
        failures += TestSupport.expect(
            !layout.canMove(.cursorModels, by: -1) && layout.canMove(.cursorModels, by: 1),
            "首项只能下移"
        )
        return failures
    }

    private static func roundTripsThroughDefaults() -> Int {
        let suite = "com.hnl1.cursorquota.tests"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return TestSupport.expect(false, "无法创建测试用 UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        var failures = TestSupport.expect(
            PanelLayout.load(from: defaults) == .default,
            "空存档应读成默认布局"
        )
        var layout = PanelLayout(order: PoolKind.allCases, hidden: [])
        layout.move(.grokBot, by: -1)
        layout.setVisible(false, for: .apiModels)
        layout.save(to: defaults)
        failures += TestSupport.expect(
            PanelLayout.load(from: defaults) == layout,
            "存档应能原样读回，实际 \(PanelLayout.load(from: defaults))"
        )
        defaults.removePersistentDomain(forName: suite)
        return failures
    }
}

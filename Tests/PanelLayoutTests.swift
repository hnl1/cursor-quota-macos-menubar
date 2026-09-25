import Foundation

enum PanelLayoutTests {
    static func run() -> Int {
        var failures = 0
        failures += defaultsToAllVisible()
        failures += fillsMissingKinds()
        failures += keepsAtLeastOneVisible()
        failures += movesWithinBounds()
        failures += movesToIndex()
        failures += dropIndexFollowsDraggedCenter()
        failures += dropIndexReachesEdgesOnTie()
        failures += roundTripsThroughDefaults()
        return failures
    }

    private static func defaultsToAllVisible() -> Int {
        let layout = PanelLayout.default
        var failures = TestSupport.expect(
            layout.visible == PoolKind.allCases,
            "默认应勾选全部额度，实际 \(layout.visible)"
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
                == PoolKind.allCases,
            "全部隐藏的存档应回退为默认，三个都勾选"
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

    private static func movesToIndex() -> Int {
        var layout = PanelLayout.default
        layout.move(.cursorModels, to: 2)
        var failures = TestSupport.expect(
            layout.order == [.apiModels, .grokBot, .cursorModels],
            "移到末位后顺序不对，实际 \(layout.order)"
        )
        layout.move(.cursorModels, to: 0)
        failures += TestSupport.expect(
            layout.order == PoolKind.allCases,
            "移回首位后顺序不对，实际 \(layout.order)"
        )
        layout.move(.apiModels, to: 9)
        failures += TestSupport.expect(
            layout.order == [.cursorModels, .grokBot, .apiModels],
            "越界下标应截到末位，实际 \(layout.order)"
        )
        layout.move(.apiModels, to: -3)
        failures += TestSupport.expect(
            layout.order == [.apiModels, .cursorModels, .grokBot],
            "负下标应截到首位，实际 \(layout.order)"
        )
        return failures
    }

    /// 坐标沿用 AppKit：y 向上，从上到下的行中点依次变小。
    private static let rowCenters: [CGFloat] = [200, 134, 68]

    private static func dropIndexFollowsDraggedCenter() -> Int {
        var failures = TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 0, draggedCenter: 180) == 0,
            "没越过下一行中点应留在原位"
        )
        failures += TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 0, draggedCenter: 120) == 1,
            "越过第二行中点应落到第二位"
        )
        failures += TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 0, draggedCenter: 20) == 2,
            "越过全部行应落到末位"
        )
        failures += TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 2, draggedCenter: 150) == 1,
            "向上越过第二行中点应落到第二位"
        )
        failures += TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 2, draggedCenter: 260) == 0,
            "向上越过全部行应落到首位"
        )
        return failures
    }

    private static func dropIndexReachesEdgesOnTie() -> Int {
        var failures = TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 1, draggedCenter: 68) == 2,
            "中点与末行重合时应落到末位"
        )
        failures += TestSupport.expect(
            PanelLayout.dropIndex(centers: rowCenters, from: 1, draggedCenter: 200) == 0,
            "中点与首行重合时应落到首位"
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

import Foundation

/// 面板里展示哪些额度、按什么顺序展示。
struct PanelLayout: Sendable, Equatable {
    private(set) var order: [PoolKind]
    private(set) var hidden: Set<PoolKind>

    static let `default` = PanelLayout()

    init(order: [PoolKind] = PoolKind.allCases, hidden: Set<PoolKind> = []) {
        var sorted: [PoolKind] = []
        for kind in order where !sorted.contains(kind) {
            sorted.append(kind)
        }
        for kind in PoolKind.allCases where !sorted.contains(kind) {
            sorted.append(kind)
        }
        self.order = sorted
        // 全部隐藏没有意义，这种数据视为没设置过。
        self.hidden = hidden.count >= sorted.count ? [] : hidden
    }

    var visible: [PoolKind] {
        order.filter { !hidden.contains($0) }
    }

    func isVisible(_ kind: PoolKind) -> Bool {
        !hidden.contains(kind)
    }

    func canMove(_ kind: PoolKind, by offset: Int) -> Bool {
        guard let index = order.firstIndex(of: kind) else { return false }
        return order.indices.contains(index + offset)
    }

    /// 至少要留一个额度，最后一个不允许再隐藏。
    func canHide(_ kind: PoolKind) -> Bool {
        isVisible(kind) ? visible.count > 1 : true
    }

    mutating func setVisible(_ visible: Bool, for kind: PoolKind) {
        if visible {
            hidden.remove(kind)
        } else if canHide(kind) {
            hidden.insert(kind)
        }
    }

    mutating func move(_ kind: PoolKind, by offset: Int) {
        guard
            let index = order.firstIndex(of: kind),
            order.indices.contains(index + offset)
        else {
            return
        }
        order.swapAt(index, index + offset)
    }
}

extension PanelLayout {
    private static let orderKey = "panel.pools.order"
    private static let hiddenKey = "panel.pools.hidden"

    static func load(from defaults: UserDefaults) -> PanelLayout {
        let order = kinds(defaults.array(forKey: orderKey))
        let hidden = kinds(defaults.array(forKey: hiddenKey))
        guard !order.isEmpty || !hidden.isEmpty else { return .default }
        return PanelLayout(order: order, hidden: Set(hidden))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(hidden.map(\.rawValue), forKey: Self.hiddenKey)
    }

    private static func kinds(_ stored: [Any]?) -> [PoolKind] {
        (stored as? [String] ?? []).compactMap(PoolKind.init(rawValue:))
    }
}

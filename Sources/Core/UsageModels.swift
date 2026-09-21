import Foundation

enum PoolKind: String, Sendable, Equatable, CaseIterable {
    case cursorModels
    case apiModels
    case grokBot

    var title: String {
        switch self {
        case .cursorModels: "Cursor 模型剩余"
        case .apiModels: "其他模型剩余"
        case .grokBot: "Grok Bot 剩余"
        }
    }

    var shortTitle: String {
        switch self {
        case .cursorModels: "Cursor 模型"
        case .apiModels: "其他模型"
        case .grokBot: "Grok Bot"
        }
    }

    var timeTitle: String {
        switch self {
        case .cursorModels, .apiModels: "周期剩余"
        case .grokBot: "本周剩余"
        }
    }

    var affectsMenuBar: Bool {
        self != .grokBot
    }
}

enum UsagePace: Int, Sendable, Equatable, Comparable {
    case onPace = 0
    case behind = 1
    case critical = 2

    static func < (lhs: UsagePace, rhs: UsagePace) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct UsageReading: Sendable, Equatable {
    let usageRemaining: Double
    let timeRemaining: Double
    let usageRemainingPercent: Int
    let timeRemainingPercent: Int
    let pace: UsagePace

    var usageRemainingFraction: Double { usageRemaining.clamped(to: 0...1) }
    var timeRemainingFraction: Double { timeRemaining.clamped(to: 0...1) }
}

struct UsagePool: Sendable, Equatable {
    let kind: PoolKind
    let usedPercent: Double
    let startsAt: Date
    let resetsAt: Date

    init?(kind: PoolKind, usedPercent: Double, startsAt: Date, resetsAt: Date) {
        let duration = resetsAt.timeIntervalSince(startsAt)
        guard
            usedPercent.isFinite,
            usedPercent >= 0,
            startsAt.timeIntervalSinceReferenceDate.isFinite,
            resetsAt.timeIntervalSinceReferenceDate.isFinite,
            duration.isFinite,
            duration > 0
        else {
            return nil
        }
        self.kind = kind
        self.usedPercent = usedPercent
        self.startsAt = startsAt
        self.resetsAt = resetsAt
    }

    var remainingUsage: Double {
        (1 - usedPercent / 100).clamped(to: 0...1)
    }

    var displayedUsedPercent: Int {
        if usedPercent > 0, usedPercent < 1 { return 1 }
        if usedPercent >= 100 { return 100 }
        return Int(usedPercent.rounded())
    }

    var displayedRemainingPercent: Int {
        100 - displayedUsedPercent
    }

    func remainingTime(at date: Date = Date()) -> Double {
        let duration = resetsAt.timeIntervalSince(startsAt)
        guard duration.isFinite, duration > 0 else { return 0 }
        let left = resetsAt.timeIntervalSince(date)
        guard left.isFinite else { return left == .infinity ? 1 : 0 }
        return (left / duration).clamped(to: 0...1)
    }

    func reading(at date: Date = Date()) -> UsageReading {
        let timeLeft = remainingTime(at: date)
        let usageLeft = remainingUsage
        let pace: UsagePace
        if usageLeft < AppConfig.criticalRemaining {
            pace = .critical
        } else if usageLeft + 0.000_001 >= timeLeft {
            pace = .onPace
        } else {
            pace = .behind
        }
        return UsageReading(
            usageRemaining: usageLeft,
            timeRemaining: timeLeft,
            usageRemainingPercent: displayedRemainingPercent,
            timeRemainingPercent: Int((timeLeft * 100).rounded()),
            pace: pace
        )
    }

    func isActive(at date: Date = Date()) -> Bool {
        resetsAt > date
    }
}

struct SpendInfo: Sendable, Equatable {
    let includedCents: Int
    let limitCents: Int
    let remainingCents: Int
    let bonusCents: Int

    var hasLimit: Bool { limitCents > 0 }

    var includedDollars: Double { Double(includedCents) / 100 }
    var limitDollars: Double { Double(limitCents) / 100 }
}

struct PlanInfo: Sendable, Equatable {
    let name: String?
    let price: String?
}

struct UsageReport: Sendable, Equatable {
    let pools: [UsagePool]
    let spend: SpendInfo?
    let plan: PlanInfo?
    let fetchedAt: Date

    init?(
        pools: [UsagePool],
        spend: SpendInfo? = nil,
        plan: PlanInfo? = nil,
        fetchedAt: Date = Date()
    ) {
        guard !pools.isEmpty else { return nil }
        self.pools = pools
        self.spend = spend
        self.plan = plan
        self.fetchedAt = fetchedAt
    }

    var billingPools: [UsagePool] {
        let filtered = pools.filter(\.kind.affectsMenuBar)
        return filtered.isEmpty ? pools : filtered
    }

    func headlinePool(
        at date: Date = Date(),
        among allowed: Set<PoolKind> = Set(PoolKind.allCases)
    ) -> UsagePool {
        let picked = billingPools.filter { allowed.contains($0.kind) }
        let candidates = picked.isEmpty ? billingPools : picked
        return candidates.max { lhs, rhs in
            let left = lhs.reading(at: date)
            let right = rhs.reading(at: date)
            if left.pace != right.pace {
                return left.pace < right.pace
            }
            return left.usageRemaining > right.usageRemaining
        } ?? pools[0]
    }

    func hasActivePool(at date: Date = Date()) -> Bool {
        billingPools.contains { $0.isActive(at: date) }
    }

    var resetDate: Date {
        billingPools.map(\.resetsAt).min() ?? pools[0].resetsAt
    }

    func replacing(plan: PlanInfo?) -> UsageReport {
        UsageReport(pools: pools, spend: spend, plan: plan, fetchedAt: fetchedAt) ?? self
    }

    func appending(_ pool: UsagePool) -> UsageReport {
        UsageReport(pools: pools + [pool], spend: spend, plan: plan, fetchedAt: fetchedAt) ?? self
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

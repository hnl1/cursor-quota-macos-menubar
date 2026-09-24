import Foundation

enum UsageParser {
    private static let cycleStartKeys = [
        "billingcyclestart", "cyclestart", "startsat", "startat"
    ]
    private static let cycleEndKeys = [
        "billingcycleend", "cycleend", "resetsat", "endat"
    ]
    private static let planUsageKeys = [
        "planusage", "usageplan", "plan"
    ]
    private static let enabledKeys = [
        "enabled", "usageenabled"
    ]
    private static let autoKeys = [
        "autopercentused", "cursormodelspercentused", "firstpartypercentused"
    ]
    private static let apiKeys = [
        "apipercentused", "apimodelspercentused"
    ]
    private static let includedKeys = [
        "includedspend", "spendused"
    ]
    private static let totalKeys = [
        "totalspend"
    ]
    private static let limitKeys = [
        "limit", "spendlimit"
    ]
    private static let remainingKeys = [
        "remaining"
    ]
    private static let bonusKeys = [
        "bonusspend"
    ]
    private static let planNameKeys = [
        "planname", "name"
    ]
    private static let planPriceKeys = [
        "price"
    ]
    private static let clockTolerance: TimeInterval = 5 * 60
    private static let maxWindow: TimeInterval = 370 * 24 * 60 * 60

    static func parseUsage(_ data: Data, at date: Date = Date()) throws -> UsageReport {
        let root = try decodeNode(data)
        var sawDisabled = false

        for node in root.unwrappedCandidates() {
            guard let object = node.object else { continue }
            if node.firstBool(for: enabledKeys) == false {
                sawDisabled = true
                continue
            }

            let planNode =
                node.value(forNormalized: planUsageKeys)
                ?? JSONNode.object(object)
            guard
                let startsAt = node.firstDate(for: cycleStartKeys),
                let resetsAt = node.firstDate(for: cycleEndKeys),
                isCurrentWindow(startsAt: startsAt, resetsAt: resetsAt, at: date)
            else {
                continue
            }

            let auto = planNode.firstNumber(for: autoKeys)
            let api = planNode.firstNumber(for: apiKeys)
            let included = planNode.firstNumber(for: includedKeys)
            let total = planNode.firstNumber(for: totalKeys)
            let limit = planNode.firstNumber(for: limitKeys)
            let remaining = planNode.firstNumber(for: remainingKeys)
            let bonus = planNode.firstNumber(for: bonusKeys) ?? 0

            var pools: [UsagePool] = []
            if let auto, let pool = UsagePool(
                kind: .cursorModels,
                usedPercent: auto,
                startsAt: startsAt,
                resetsAt: resetsAt
            ) {
                pools.append(pool)
            }
            if let api, let pool = UsagePool(
                kind: .apiModels,
                usedPercent: api,
                startsAt: startsAt,
                resetsAt: resetsAt
            ) {
                pools.append(pool)
            }

            let spend = spendInfo(
                included: included,
                total: total,
                limit: limit,
                remaining: remaining,
                bonus: bonus
            )

            if let report = UsageReport(pools: pools, spend: spend, fetchedAt: date) {
                return report
            }
        }

        throw sawDisabled ? QuotaError.usageDisabled : QuotaError.unexpectedPayload
    }

    static func parsePlan(_ data: Data) -> PlanInfo? {
        guard let root = try? decodeNode(data) else { return nil }
        for node in root.unwrappedCandidates() {
            let planNode = node.value(forNormalized: ["planinfo", "plan"]) ?? node
            let name = planNode.value(forNormalized: planNameKeys)?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let price = planNode.value(forNormalized: planPriceKeys)?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty {
                return PlanInfo(
                    name: name,
                    price: (price?.isEmpty == false) ? price : nil
                )
            }
        }
        return nil
    }

    /// 返回 nil 表示账号本来就没有 Grok Bot 额度；数据认不出来时抛错。
    static func parseGrokBot(_ data: Data, at date: Date = Date()) throws -> UsagePool? {
        let root = try decodeNode(data)
        var notIncluded = false
        for node in root.unwrappedCandidates() {
            if node.firstBool(for: ["hasnonzeroincludedlimit"]) == false {
                notIncluded = true
                continue
            }
            guard
                let used = node.firstNumber(for: ["usagepercent"]),
                let startsAt = node.firstDate(for: [
                    "currentperiodstart", "periodstart", "startsat"
                ]),
                let resetsAt = node.firstDate(for: [
                    "nextresettimestamputc", "currentperiodend", "resetsat", "endat"
                ]),
                isCurrentWindow(startsAt: startsAt, resetsAt: resetsAt, at: date)
            else {
                continue
            }
            if let pool = UsagePool(
                kind: .grokBot,
                usedPercent: used,
                startsAt: startsAt,
                resetsAt: resetsAt
            ) {
                return pool
            }
        }
        guard notIncluded else { throw QuotaError.unexpectedPayload }
        return nil
    }

    private static func decodeNode(_ data: Data) throws -> JSONNode {
        do {
            return try JSONDecoder().decode(JSONNode.self, from: data)
        } catch {
            throw QuotaError.unexpectedPayload
        }
    }

    private static func spendInfo(
        included: Double?,
        total: Double?,
        limit: Double?,
        remaining: Double?,
        bonus: Double
    ) -> SpendInfo? {
        let includedCents = included.flatMap(cents)
        let totalCents = total.flatMap(cents)
        let limitCents = limit.flatMap(cents)
        let remainingCents = remaining.flatMap(cents)
        let bonusCents = cents(bonus) ?? 0
        guard includedCents != nil || limitCents != nil || totalCents != nil else { return nil }
        let resolvedLimit = limitCents ?? 0
        let resolvedIncluded = includedCents ?? 0
        let resolvedRemaining = remainingCents ?? max(resolvedLimit - resolvedIncluded, 0)
        return SpendInfo(
            includedCents: resolvedIncluded,
            limitCents: resolvedLimit,
            remainingCents: resolvedRemaining,
            bonusCents: bonusCents,
            totalCents: totalCents
        )
    }

    private static func cents(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    private static func isCurrentWindow(startsAt: Date, resetsAt: Date, at date: Date) -> Bool {
        let duration = resetsAt.timeIntervalSince(startsAt)
        guard duration.isFinite, duration > 0, duration <= maxWindow else { return false }
        let now = date.timeIntervalSinceReferenceDate
        return startsAt.timeIntervalSinceReferenceDate <= now + clockTolerance
            && resetsAt.timeIntervalSinceReferenceDate >= now - clockTolerance
    }
}

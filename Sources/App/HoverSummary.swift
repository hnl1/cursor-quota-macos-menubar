import AppKit
import Foundation

struct HoverSummary: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let title: String
        let detail: String
        let pace: UsagePace?
    }

    let title: String
    let status: String
    let rows: [Row]
    let footnote: String?

    static func make(
        report: UsageReport?,
        stale: String?,
        at date: Date = Date()
    ) -> HoverSummary {
        guard let report else {
            return HoverSummary(
                title: AppConfig.appName,
                status: "不可用",
                rows: [],
                footnote: stale
            )
        }

        var rows: [Row] = []
        for pool in report.pools where pool.kind.affectsMenuBar {
            let reading = pool.reading(at: date)
            rows.append(
                Row(
                    title: pool.kind.shortTitle,
                    detail: "剩余 \(reading.usageRemainingPercent)% · 周期 \(reading.timeRemainingPercent)%",
                    pace: reading.pace
                )
            )
        }

        var notes: [String] = []
        var planParts: [String] = []
        if let name = report.plan?.name, !name.isEmpty {
            planParts.append(name)
        }
        if let price = report.plan?.price, !price.isEmpty {
            planParts.append(price)
        }
        if let spend = report.spend, spend.hasLimit {
            planParts.append(
                "\(Theme.currency(spend.includedDollars)) / \(Theme.currency(spend.limitDollars))"
            )
        }
        if !planParts.isEmpty {
            notes.append(planParts.joined(separator: " · "))
        }
        notes.append(Theme.resetText(from: report.resetDate))
        if let stale {
            notes.append("上次成功结果 · \(stale)")
        }

        return HoverSummary(
            title: AppConfig.appName,
            status: stale == nil ? "实时" : "过期",
            rows: rows,
            footnote: notes.joined(separator: "\n")
        )
    }

    static func loading() -> HoverSummary {
        HoverSummary(
            title: AppConfig.appName,
            status: "更新中",
            rows: [Row(title: "正在读取 Cursor 用量", detail: "", pace: nil)],
            footnote: nil
        )
    }

    static func unavailable(_ message: String) -> HoverSummary {
        HoverSummary(
            title: AppConfig.appName,
            status: "不可用",
            rows: [Row(title: message, detail: "", pace: nil)],
            footnote: nil
        )
    }
}

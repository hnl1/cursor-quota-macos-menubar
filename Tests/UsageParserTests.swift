import Foundation

enum UsageParserTests {
    static func run() -> Int {
        var failed = 0
        let now = Date(timeIntervalSince1970: 1_789_996_000)
        let live = """
        {
          "billingCycleStart": "1789961823000",
          "billingCycleEnd": "1792553823000",
          "planUsage": {
            "totalSpend": 754,
            "includedSpend": 754,
            "remaining": 39246,
            "limit": 40000,
            "autoPercentUsed": 0.247,
            "apiPercentUsed": 0.052,
            "totalPercentUsed": 0.232
          },
          "enabled": true
        }
        """.data(using: .utf8)!

        do {
            let report = try UsageParser.parseUsage(live, at: now)
            failed += TestSupport.expect(report.pools.count == 2, "split pools should both parse")
            failed += TestSupport.expect(
                report.pools.contains(where: { $0.kind == .cursorModels && $0.usedPercent == 0.247 }),
                "auto pool maps to Cursor models"
            )
            failed += TestSupport.expect(
                report.pools.contains(where: { $0.kind == .apiModels && $0.usedPercent == 0.052 }),
                "api pool maps to other models"
            )
            failed += TestSupport.expect(report.spend?.includedCents == 754, "included spend is 754 cents")
            failed += TestSupport.expect(report.spend?.totalCents == 754, "total spend is 754 cents")
            failed += TestSupport.expect(report.spend?.limitCents == 40000, "limit is 40000 cents")
        } catch {
            failed += TestSupport.expect(false, "live payload should parse: \(error)")
        }

        let overIncluded = """
        {
          "billingCycleStart": "1789961823000",
          "billingCycleEnd": "1792553823000",
          "planUsage": {
            "totalSpend": 62120,
            "includedSpend": 40000,
            "bonusSpend": 22120,
            "limit": 40000,
            "autoPercentUsed": 17.63,
            "apiPercentUsed": 36.93
          },
          "enabled": true
        }
        """.data(using: .utf8)!
        do {
            let report = try UsageParser.parseUsage(overIncluded, at: now)
            failed += TestSupport.expect(report.spend?.totalCents == 62120, "total spend stays above the included cap")
            failed += TestSupport.expect(report.spend?.includedCents == 40000, "included spend stays capped")
        } catch {
            failed += TestSupport.expect(false, "over-included payload should parse: \(error)")
        }

        let wrapped = """
        {
          "data": {
            "billingCycleStart": "2026-09-21T00:00:00Z",
            "billingCycleEnd": "2026-10-21T00:00:00Z",
            "planUsage": {
              "autoPercentUsed": 12.5,
              "apiPercentUsed": 4,
              "includedSpend": 500,
              "limit": 2000
            }
          }
        }
        """.data(using: .utf8)!
        do {
            let report = try UsageParser.parseUsage(wrapped, at: now)
            failed += TestSupport.expect(report.pools.count == 2, "wrapped dual-pool payload parses")
            failed += TestSupport.expect(
                report.pools.contains(where: { $0.kind == .cursorModels && $0.usedPercent == 12.5 }),
                "wrapped auto pool maps"
            )
            failed += TestSupport.expect(report.spend?.totalCents == nil, "missing totalSpend stays unset")
        } catch {
            failed += TestSupport.expect(false, "wrapped payload should parse: \(error)")
        }

        let totalOnly = """
        {
          "billingCycleStart": "2026-09-21T00:00:00Z",
          "billingCycleEnd": "2026-10-21T00:00:00Z",
          "planUsage": {
            "totalPercentUsed": 25,
            "includedSpend": 500,
            "limit": 2000
          },
          "enabled": true
        }
        """.data(using: .utf8)!
        do {
            _ = try UsageParser.parseUsage(totalOnly, at: now)
            failed += TestSupport.expect(false, "total-only payload should be rejected")
        } catch let error as QuotaError {
            failed += TestSupport.expect(error == .unexpectedPayload, "total-only maps to unexpectedPayload")
        } catch {
            failed += TestSupport.expect(false, "total-only should be QuotaError")
        }

        let disabled = """
        {
          "enabled": false,
          "billingCycleStart": "1789961823000",
          "billingCycleEnd": "1792553823000",
          "planUsage": { "totalPercentUsed": 10 }
        }
        """.data(using: .utf8)!
        do {
            _ = try UsageParser.parseUsage(disabled, at: now)
            failed += TestSupport.expect(false, "disabled usage should fail")
        } catch let error as QuotaError {
            failed += TestSupport.expect(error == .usageDisabled, "disabled usage maps to usageDisabled")
        } catch {
            failed += TestSupport.expect(false, "disabled usage should be QuotaError")
        }

        let plan = """
        {
          "planInfo": {
            "planName": "Ultra",
            "price": "$200/mo"
          }
        }
        """.data(using: .utf8)!
        let info = UsageParser.parsePlan(plan)
        failed += TestSupport.expect(info?.name == "Ultra", "plan name Ultra")
        failed += TestSupport.expect(info?.price == "$200/mo", "plan price parses")

        let grok = """
        {
          "currentPeriodStart": "2026-09-17T17:12:27.361Z",
          "nextResetTimestampUtc": "2026-09-24T17:12:27.361Z",
          "usagePercent": 0,
          "hasNonZeroIncludedLimit": true
        }
        """.data(using: .utf8)!
        let grokPool = try? UsageParser.parseGrokBot(grok, at: now)
        failed += TestSupport.expect(grokPool?.kind == .grokBot, "grok bot pool parses")
        failed += TestSupport.expect(grokPool?.usedPercent == 0, "grok bot unused")
        failed += TestSupport.expect(grokPool?.displayedRemainingPercent == 100, "grok bot 0% used -> 100% left")

        let grokDisabled = """
        {
          "currentPeriodStart": "2026-09-17T17:12:27.361Z",
          "nextResetTimestampUtc": "2026-09-24T17:12:27.361Z",
          "usagePercent": 10,
          "hasNonZeroIncludedLimit": false
        }
        """.data(using: .utf8)!
        do {
            let pool = try UsageParser.parseGrokBot(grokDisabled, at: now)
            failed += TestSupport.expect(pool == nil, "grok bot without included limit is ignored")
        } catch {
            failed += TestSupport.expect(false, "grok bot without included limit should not throw")
        }

        let grokPayloads = [
            "not json",
            #"{"usagePercent": 10}"#
        ]
        for payload in grokPayloads {
            do {
                _ = try UsageParser.parseGrokBot(Data(payload.utf8), at: now)
                failed += TestSupport.expect(false, "unrecognized grok bot payload should throw: \(payload)")
            } catch let error as QuotaError {
                failed += TestSupport.expect(
                    error == .unexpectedPayload,
                    "unrecognized grok bot payload maps to unexpectedPayload: \(payload)"
                )
            } catch {
                failed += TestSupport.expect(false, "unrecognized grok bot payload should be QuotaError")
            }
        }
        return failed
    }
}

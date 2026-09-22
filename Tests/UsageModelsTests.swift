import Foundation

enum UsageModelsTests {
    static func run() -> Int {
        var failed = 0
        let start = TestSupport.date(1_000_000)
        let end = TestSupport.date(1_000_000 + 100)

        let pool = UsagePool(
            kind: .cursorModels,
            usedPercent: 20,
            startsAt: start,
            resetsAt: end
        )
        failed += TestSupport.expect(pool != nil, "valid pool should be created")

        if let pool {
            let mid = TestSupport.date(1_000_000 + 40)
            let reading = pool.reading(at: mid)
            failed += TestSupport.expect(reading.usageRemainingPercent == 80, "20% used -> 80% left")
            failed += TestSupport.expect(reading.timeRemainingPercent == 60, "40/100 elapsed -> 60% time left")
            failed += TestSupport.expect(reading.pace == .onPace, "80% usage left vs 60% time left is on pace")
        }

        let tinyUsed = UsagePool(
            kind: .apiModels,
            usedPercent: 0.4,
            startsAt: start,
            resetsAt: end
        )
        failed += TestSupport.expect(tinyUsed?.displayedUsedPercent == 1, "sub-1% used displays as 1%")
        failed += TestSupport.expect(tinyUsed?.displayedRemainingPercent == 99, "sub-1% used leaves 99%")

        let behind = UsagePool(
            kind: .cursorModels,
            usedPercent: 70,
            startsAt: start,
            resetsAt: end
        )!.reading(at: TestSupport.date(1_000_000 + 20))
        failed += TestSupport.expect(behind.pace == .behind, "30% usage left vs 80% time left is behind")

        let critical = UsagePool(
            kind: .cursorModels,
            usedPercent: 90,
            startsAt: start,
            resetsAt: end
        )!.reading(at: TestSupport.date(1_000_000 + 90))
        failed += TestSupport.expect(critical.pace == .critical, "10% remaining is critical even if time is lower")

        let invalid = UsagePool(
            kind: .cursorModels,
            usedPercent: 10,
            startsAt: end,
            resetsAt: start
        )
        failed += TestSupport.expect(invalid == nil, "inverted window is rejected")

        let tight = UsagePool(kind: .apiModels, usedPercent: 40, startsAt: start, resetsAt: end)!
        let loose = UsagePool(kind: .cursorModels, usedPercent: 10, startsAt: start, resetsAt: end)!
        let report = UsageReport(pools: [loose, tight])
        failed += TestSupport.expect(
            report?.headlinePool(at: start).kind == .apiModels,
            "headline pool should be the tighter quota"
        )

        let grokTight = UsagePool(
            kind: .grokBot,
            usedPercent: 90,
            startsAt: start,
            resetsAt: end
        )!
        let withGrok = UsageReport(pools: [loose, tight, grokTight])
        failed += TestSupport.expect(
            withGrok?.headlinePool(at: start).kind == .apiModels,
            "grok bot must not replace the menubar headline"
        )
        failed += TestSupport.expect(
            withGrok?.resetDate == end,
            "reset date stays on the billing window"
        )

        let fetched = TestSupport.date(2_000_000)
        let aged = UsageReport(pools: [loose], fetchedAt: fetched)
        failed += TestSupport.expect(
            aged?.isStale(at: fetched.addingTimeInterval(AppConfig.staleAfter)) == false,
            "data exactly 30 minutes old is not stale"
        )
        failed += TestSupport.expect(
            aged?.isStale(at: fetched.addingTimeInterval(AppConfig.staleAfter + 1)) == true,
            "data older than 30 minutes is stale"
        )
        return failed
    }
}

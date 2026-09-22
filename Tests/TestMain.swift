import Foundation

@main
enum TestMain {
    static func main() {
        var failures = 0
        let suites: [() -> Int] = [
            UsageModelsTests.run,
            UsageParserTests.run,
            PanelLayoutTests.run,
            MenuBarOptionsTests.run
        ]
        for suite in suites {
            failures += suite()
        }
        if failures > 0 {
            fputs("FAILED \(failures) assertion(s)\n", stderr)
            exit(1)
        }
        print("All tests passed")
    }
}

enum TestSupport {
    @discardableResult
    static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Int {
        guard !condition else { return 0 }
        fputs("FAIL \(file):\(line) \(message)\n", stderr)
        return 1
    }

    static func date(_ unixSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: unixSeconds)
    }
}

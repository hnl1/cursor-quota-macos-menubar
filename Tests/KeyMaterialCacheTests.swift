import Foundation

private struct Probe: Error {}

enum KeyMaterialCacheTests {
    static func run() -> Int {
        var failures = 0
        failures += reusesFirstPassword()
        failures += doesNotCacheFailure()
        failures += reentryDoesNotReadAgain()
        return failures
    }

    private static func reusesFirstPassword() -> Int {
        let cache = KeyMaterialCache()
        do {
            let first = try cache.value { Data("pw".utf8) }
            let second = try cache.value { throw Probe() }
            var failures = TestSupport.expect(first == Data("pw".utf8), "第一次应读到口令")
            failures += TestSupport.expect(second == first, "第二次应复用第一次的口令")
            return failures
        } catch {
            return TestSupport.expect(false, "复用口令时抛错 \(error)")
        }
    }

    private static func doesNotCacheFailure() -> Int {
        let cache = KeyMaterialCache()
        do {
            _ = try cache.value { throw Probe() }
            return TestSupport.expect(false, "读取失败时应抛错")
        } catch is Probe {
            do {
                let recovered = try cache.value { Data([1]) }
                return TestSupport.expect(recovered == Data([1]), "失败后应重新读取")
            } catch {
                return TestSupport.expect(false, "失败后的再次读取抛错 \(error)")
            }
        } catch {
            return TestSupport.expect(false, "读取失败抛了别的错 \(error)")
        }
    }

    private static func reentryDoesNotReadAgain() -> Int {
        let cache = KeyMaterialCache()
        do {
            _ = try cache.value {
                try cache.value { Data([2]) }
            }
            return TestSupport.expect(false, "读取过程中再次进入应失败")
        } catch let error as QuotaError {
            var failures = TestSupport.expect(error == .databaseBusy, "重入应算正在读取，实际 \(error)")
            do {
                let after = try cache.value { Data([3]) }
                failures += TestSupport.expect(after == Data([3]), "重入失败后应还能再读")
            } catch {
                failures += TestSupport.expect(false, "重入失败后的再次读取抛错 \(error)")
            }
            return failures
        } catch {
            return TestSupport.expect(false, "重入抛了别的错 \(error)")
        }
    }
}

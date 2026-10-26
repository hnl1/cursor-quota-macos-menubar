import Foundation

enum SessionStoreTests {
    private static let plaintext = "cursor-session-token"
    /// 由 test-password 按 Chromium OSCrypt（PBKDF2-SHA1、AES-128-CBC、v10）封出来的固定样本。
    private static let sealed =
        "cursor-safe-storage:v1:djEwrzyxzh219kFggS1ypTHGXWOeeAnx+zTpV9ZA6i7Ei+k="

    private static let password = Data("test-password".utf8)

    static func run() -> Int {
        var failures = 0
        failures += sealedTokenIsRestored()
        failures += plaintextStaysPlaintextWhenFlagIsOn()
        failures += wrongPasswordIsUnreadable()
        failures += malformedEnvelopeIsUnreadable()
        return failures
    }

    private static func sealedTokenIsRestored() -> Int {
        let database: URL
        do {
            database = try makeDatabase(
                rows: [
                    "cursorAuth/accessToken": sealed,
                    "cursorAuth/stripeMembershipType": "ultra",
                    "cursor.storage.authTokenEncryptionAtRest": "false",
                ]
            )
        } catch {
            return TestSupport.expect(false, "无法准备加密令牌数据库 \(error)")
        }
        defer { try? FileManager.default.removeItem(at: database) }

        do {
            let session = try SessionStore.load(from: database) { password }
            var failures = TestSupport.expect(
                session.accessToken == plaintext,
                "带 cursor-safe-storage 前缀的 accessToken 应还原成明文，实际 \(session.accessToken)"
            )
            failures += TestSupport.expect(
                session.membershipType == "ultra",
                "套餐类型应仍能读出，实际 \(session.membershipType ?? "nil")"
            )
            return failures
        } catch {
            return TestSupport.expect(false, "读取封存令牌时抛错 \(error)")
        }
    }

    private static func plaintextStaysPlaintextWhenFlagIsOn() -> Int {
        let database: URL
        do {
            database = try makeDatabase(
                rows: [
                    "cursorAuth/accessToken": plaintext,
                    "cursor.storage.authTokenEncryptionAtRest": "true",
                ]
            )
        } catch {
            return TestSupport.expect(false, "无法准备明文令牌数据库 \(error)")
        }
        defer { try? FileManager.default.removeItem(at: database) }

        do {
            let session = try SessionStore.load(from: database) { throw QuotaError.offline }
            return TestSupport.expect(
                session.accessToken == plaintext,
                "开关为 true 时明文令牌也应原样使用，实际 \(session.accessToken)"
            )
        } catch {
            return TestSupport.expect(false, "读取明文令牌时抛错 \(error)")
        }
    }

    private static func wrongPasswordIsUnreadable() -> Int {
        let database: URL
        do {
            database = try makeDatabase(rows: ["cursorAuth/accessToken": sealed])
        } catch {
            return TestSupport.expect(false, "无法准备错误口令数据库 \(error)")
        }
        defer { try? FileManager.default.removeItem(at: database) }

        do {
            _ = try SessionStore.load(from: database) { Data("other-password".utf8) }
            return TestSupport.expect(false, "错误口令不应解出令牌")
        } catch let error as QuotaError {
            return TestSupport.expect(error == .loginUnreadable, "错误口令应报无法读取，实际 \(error)")
        } catch {
            return TestSupport.expect(false, "错误口令抛了别的错 \(error)")
        }
    }

    private static func malformedEnvelopeIsUnreadable() -> Int {
        let database: URL
        do {
            database = try makeDatabase(
                rows: ["cursorAuth/accessToken": "cursor-safe-storage:v1:not-base64!!!"]
            )
        } catch {
            return TestSupport.expect(false, "无法准备损坏封包数据库 \(error)")
        }
        defer { try? FileManager.default.removeItem(at: database) }

        do {
            _ = try SessionStore.load(from: database) { password }
            return TestSupport.expect(false, "损坏的封包不应解出令牌")
        } catch let error as QuotaError {
            return TestSupport.expect(error == .loginUnreadable, "损坏的封包应报无法读取，实际 \(error)")
        } catch {
            return TestSupport.expect(false, "损坏的封包抛了别的错 \(error)")
        }
    }

    private static func makeDatabase(rows: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-quota-\(UUID().uuidString).vscdb")
        var sql = "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);\n"
        for (key, value) in rows {
            sql += "INSERT INTO ItemTable (key, value) VALUES ('\(sqlLiteral(key))', '\(sqlLiteral(value))');\n"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private static func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

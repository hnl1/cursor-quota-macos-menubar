import Foundation
import Security
import SQLite3

struct CursorSession: Sendable, Equatable {
    let accessToken: String
    let membershipType: String?
}

enum SessionStore {
    private static let tokenKey = "cursorAuth/accessToken"
    private static let membershipKey = "cursorAuth/stripeMembershipType"
    private static let maxTokenBytes = 16_384
    private static let keychainCache = KeyMaterialCache()

    static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
            .appendingPathComponent("state.vscdb")
    }

    static func load(
        from databaseURL: URL = defaultDatabaseURL,
        keyMaterial: @escaping @Sendable () throws -> Data = {
            try keychainCache.value {
                ProbeLog.write("keychain.load")
                return try readKeychainPassword()
            }
        }
    ) throws -> CursorSession {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw QuotaError.cursorNotOpened
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
            let database
        else {
            if database != nil {
                sqlite3_close(database)
            }
            throw QuotaError.databaseBusy
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)

        let values = try readValues(
            from: database,
            keys: [tokenKey, membershipKey]
        )
        let stored = try sanitizedToken(values[tokenKey])
        let token = try unwrap(stored, keyMaterial: keyMaterial)
        let membership = values[membershipKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CursorSession(
            accessToken: try sanitizedToken(token),
            membershipType: (membership?.isEmpty == false) ? membership : nil
        )
    }

    private static func unwrap(
        _ stored: String,
        keyMaterial: @Sendable () throws -> Data
    ) throws -> String {
        guard SafeStorageSeal.isSealed(stored) else { return stored }
        let password: Data
        do {
            password = try keyMaterial()
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.loginUnreadable
        }
        return try SafeStorageSeal.open(stored, password: password)
    }

    /// 在调用线程是主线程时先让开。抢回主线程再读时，同一次 SecItemCopyMatching 会弹出两个授权框。
    private static func readKeychainPassword() throws -> Data {
        if Thread.isMainThread {
            return try DispatchQueue.global(qos: .userInitiated).sync {
                try copySafeStoragePassword()
            }
        }
        return try copySafeStoragePassword()
    }

    private static func copySafeStoragePassword() throws -> Data {
        ProbeLog.write("SecItemCopyMatching begin", stack: true)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        ProbeLog.write("SecItemCopyMatching end status=\(status) bytes=\((item as? Data)?.count ?? -1)")
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else {
            throw QuotaError.loginUnreadable
        }
        return data
    }

    private static func readValues(
        from database: OpaquePointer,
        keys: [String]
    ) throws -> [String: String] {
        let sql = "SELECT key, value FROM ItemTable WHERE key = ? LIMIT 1"
        var result: [String: String] = [:]
        for key in keys {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                let statement
            else {
                throw QuotaError.databaseBusy
            }
            defer { sqlite3_finalize(statement) }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK else {
                throw QuotaError.databaseBusy
            }

            let step = sqlite3_step(statement)
            if step == SQLITE_BUSY {
                throw QuotaError.databaseBusy
            }
            guard step == SQLITE_ROW else { continue }
            guard let bytes = sqlite3_column_text(statement, 1) else { continue }
            let count = sqlite3_column_bytes(statement, 1)
            guard count > 0, count <= maxTokenBytes else { continue }
            let data = Data(bytes: bytes, count: Int(count))
            if let text = String(data: data, encoding: .utf8) {
                result[key] = text
            }
        }
        return result
    }

    private static func sanitizedToken(_ raw: String?) throws -> String {
        guard let raw else { throw QuotaError.notSignedIn }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw QuotaError.notSignedIn }
        guard !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw QuotaError.notSignedIn
        }
        return token
    }
}

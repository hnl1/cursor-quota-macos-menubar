import Foundation
import Synchronization

/// 同一次运行里钥匙串只读一次。系统按次弹授权，用量刷新会反复进来。
final class KeyMaterialCache: Sendable {
    private struct State: Sendable {
        var password: Data?
        var reading = false
    }

    private let state = Mutex(State())

    func value(_ load: @Sendable () throws -> Data) throws -> Data {
        let decision = state.withLock { state -> Decision in
            if let password = state.password { return .cached(password) }
            if state.reading { return .busy }
            state.reading = true
            return .read
        }
        switch decision {
        case .cached(let password):
            return password
        case .busy:
            throw QuotaError.databaseBusy
        case .read:
            do {
                let password = try load()
                state.withLock { state in
                    state.password = password
                    state.reading = false
                }
                return password
            } catch {
                state.withLock { state in
                    state.reading = false
                }
                throw error
            }
        }
    }

    private enum Decision {
        case cached(Data)
        case busy
        case read
    }
}

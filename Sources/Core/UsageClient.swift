import Foundation

protocol UsageFetching: Sendable {
    func fetch() async throws -> UsageReport
}

struct UsageClient: UsageFetching {
    private let sessionLoader: @Sendable () throws -> CursorSession
    private let now: @Sendable () -> Date
    private let transport: any HTTPTransport

    init(
        sessionLoader: @escaping @Sendable () throws -> CursorSession = { try SessionStore.load() },
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessionLoader = sessionLoader
        self.transport = transport
        self.now = now
    }

    func fetch() async throws -> UsageReport {
        let session = try sessionLoader()
        let usageData = try await transport.post(
            url: AppConfig.usageURL,
            token: session.accessToken
        )
        var report = try UsageParser.parseUsage(usageData, at: now())
        if let planData = try? await transport.post(
            url: AppConfig.planURL,
            token: session.accessToken
        ), let plan = UsageParser.parsePlan(planData) {
            report = report.replacing(plan: plan)
        } else if report.plan == nil, let membership = session.membershipType {
            report = report.replacing(plan: PlanInfo(name: membership.capitalized, price: nil))
        }
        if let grokData = try? await transport.post(
            url: AppConfig.grokBotURL,
            token: session.accessToken
        ), let grok = UsageParser.parseGrokBot(grokData, at: now()) {
            report = report.appending(grok)
        }
        return report
    }
}

protocol HTTPTransport: Sendable {
    func post(url: URL, token: String) async throws -> Data
}

struct URLSessionTransport: HTTPTransport {
    func post(url: URL, token: String) async throws -> Data {
        guard AppConfig.isAllowed(url) else { throw QuotaError.unexpectedPayload }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: AppConfig.requestTimeout
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.timeoutIntervalForResource = AppConfig.requestTimeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let session = URLSession(
            configuration: configuration,
            delegate: RedirectGuard(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled {
                if Task.isCancelled { throw CancellationError() }
                throw QuotaError.offline
            }
            if error.code == .timedOut { throw QuotaError.timedOut }
            throw QuotaError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw QuotaError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.unexpectedPayload
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw QuotaError.loginExpired
        case 408, 504:
            throw QuotaError.timedOut
        case 429:
            throw QuotaError.rateLimited
        default:
            throw QuotaError.server
        }
        guard data.count <= AppConfig.maxResponseBytes else {
            throw QuotaError.unexpectedPayload
        }
        return data
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

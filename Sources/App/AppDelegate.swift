import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let client: any UsageFetching
    private let menu = NSMenu()
    private let dashboardItem = NSMenuItem()
    private let dashboard = PopoverController()

    private var statusItem: NSStatusItem?
    private var report: UsageReport?
    private var staleMessage: String?
    private var refreshTask: Task<Void, Never>?
    private var usageTimer: Timer?
    private var clockTimer: Timer?
    private var hookRefreshTask: Task<Void, Never>?
    private var pendingRefresh: PendingRefresh = .none
    private var refreshObserver: NSObjectProtocol?
    private var hookObserver: NSObjectProtocol?
    private var layout = PanelLayout.load(from: .standard)
    private var menuBarOptions = MenuBarOptions.load(from: .standard)
    private var scene: MenuBarScene = .loading

    init(client: any UsageFetching = UsageClient()) {
        self.client = client
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        configureExternalRefresh()
        scheduleTimers()
        refresh()
        NSApp.deactivate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        usageTimer?.invalidate()
        clockTimer?.invalidate()
        hookRefreshTask?.cancel()
        if let refreshObserver {
            DistributedNotificationCenter.default().removeObserver(refreshObserver)
        }
        if let hookObserver {
            DistributedNotificationCenter.default().removeObserver(hookObserver)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = nil
        button.setAccessibilityLabel(AppConfig.appName)
        item.autosaveName = "com.hnl1.cursorquota.menubar"
        item.behavior = [.removalAllowed]
        UserDefaults.standard.set(10_000, forKey: "NSStatusItem Preferred Position com.hnl1.cursorquota.menubar")
        item.menu = menu
        item.isVisible = true
        render(.loading)
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self
        dashboard.onRefresh = { [weak self] in self?.refresh() }
        dashboard.onContentSizeChange = { [weak self] size in
            self?.applyDashboardSize(size)
        }
        dashboard.onLayoutChange = { [weak self] layout in
            self?.applyLayout(layout)
        }
        dashboard.onShowsPercentChange = { [weak self] showsPercent in
            self?.applyShowsPercent(showsPercent)
        }
        _ = dashboard.view
        dashboard.apply(layout: layout)
        dashboard.apply(showsPercent: menuBarOptions.showsPercent)
        dashboardItem.view = dashboard.view
        menu.addItem(dashboardItem)
    }

    private func applyDashboardSize(_ size: NSSize) {
        dashboard.view.frame = NSRect(origin: .zero, size: size)
        dashboardItem.view = dashboard.view
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func applyLayout(_ layout: PanelLayout) {
        self.layout = layout
        layout.save(to: .standard)
        if let report {
            updateMenuBar(with: report, stale: staleMessage)
        }
    }

    private func applyShowsPercent(_ showsPercent: Bool) {
        menuBarOptions.showsPercent = showsPercent
        menuBarOptions.save(to: .standard)
        render(scene)
    }

    private func configureExternalRefresh() {
        refreshObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppConfig.refreshNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        hookObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppConfig.hookNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromHook()
            }
        }
    }

    private func refreshFromHook() {
        if refreshTask != nil {
            pendingRefresh = .afterHookDelay
            return
        }
        hookRefreshTask?.cancel()
        hookRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConfig.hookRefreshDelay))
            guard !Task.isCancelled else { return }
            self?.refresh(origin: .hook)
        }
    }

    private func scheduleTimers() {
        let usage = Timer(timeInterval: AppConfig.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        usage.tolerance = AppConfig.refreshInterval / 10
        RunLoop.main.add(usage, forMode: .common)
        usageTimer = usage

        let clock = Timer(timeInterval: AppConfig.clockInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        clock.tolerance = 5
        RunLoop.main.add(clock, forMode: .common)
        clockTimer = clock
    }

    private func refresh(origin: RefreshOrigin = .direct) {
        if refreshTask != nil {
            if origin == .hook {
                if pendingRefresh != .afterHookDelay {
                    pendingRefresh = .now
                }
            } else {
                pendingRefresh = .now
            }
            return
        }
        pendingRefresh = .none
        dashboard.showLoading()
        if report == nil {
            render(.loading)
        }

        refreshTask = Task { [client] in
            let outcome: Result<UsageReport, Error>
            do {
                outcome = .success(try await client.fetch())
            } catch is CancellationError {
                await MainActor.run {
                    self.refreshTask = nil
                    self.followUpRefresh()
                }
                return
            } catch {
                outcome = .failure(error)
            }

            await MainActor.run {
                self.refreshTask = nil
                switch outcome {
                case .success(let report):
                    self.apply(report: report)
                case .failure(let error):
                    self.apply(error: error)
                }
                self.followUpRefresh()
            }
        }
    }

    private func followUpRefresh() {
        switch pendingRefresh {
        case .none:
            break
        case .now:
            pendingRefresh = .none
            refresh(origin: .direct)
        case .afterHookDelay:
            pendingRefresh = .none
            refreshFromHook()
        }
    }

    private enum RefreshOrigin {
        case direct
        case hook
    }

    private enum PendingRefresh {
        case none
        case now
        case afterHookDelay
    }

    private func tick(at date: Date = Date()) {
        if let report, let staleMessage, !report.hasActivePool(at: date) {
            showUnavailable(staleMessage)
            return
        }
        dashboard.updateClock(at: date)
        if let report {
            updateMenuBar(with: report, at: date, stale: staleMessage)
        }
    }

    private func apply(report: UsageReport) {
        self.report = report
        staleMessage = nil
        dashboard.show(report: report)
        updateMenuBar(with: report, stale: nil)
    }

    private func apply(error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? "无法读取 Cursor 用量。"
        let keepLast = (error as? QuotaError)?.keepsLastReading ?? true
        if keepLast, let report, report.hasActivePool() {
            staleMessage = message
            dashboard.show(report: report, staleMessage: message)
            updateMenuBar(with: report, stale: message)
        } else {
            showUnavailable(message)
        }
    }

    private func showUnavailable(_ message: String) {
        report = nil
        staleMessage = nil
        dashboard.showError(message)
        render(.unavailable)
        statusItem?.button?.setAccessibilityValue("用量不可用")
    }

    private func updateMenuBar(
        with report: UsageReport,
        at date: Date = Date(),
        stale: String?
    ) {
        let picked = layout.visible.compactMap { kind in
            report.pools.first { $0.kind == kind }
        }
        let pools = picked.isEmpty
            ? [report.headlinePool(at: date, among: Set(layout.visible))]
            : picked
        let readings = pools.map { $0.reading(at: date) }
        render(.readings(readings, isStale: stale != nil))
        statusItem?.button?.setAccessibilityValue(
            zip(pools, readings)
                .map { pool, reading in
                    "\(pool.kind.shortTitle)剩余 \(reading.usageRemainingPercent)%，"
                        + "\(pool.kind.timeTitle) \(reading.timeRemainingPercent)%"
                }
                .joined(separator: "；")
        )
    }

    private func render(_ scene: MenuBarScene) {
        self.scene = scene
        guard let button = statusItem?.button else { return }
        // 圆环和百分比一起画进图里：多组并排时没法交给按钮的 title 排版。
        button.image = GaugeImage.image(for: scene, showsPercent: menuBarOptions.showsPercent)
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }
}

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let client: any UsageFetching
    private let popover = NSPopover()
    private let popoverController = PopoverController()

    private var statusItem: NSStatusItem?
    private var report: UsageReport?
    private var staleMessage: String?
    private var refreshTask: Task<Void, Never>?
    private var usageTimer: Timer?
    private var clockTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private let hoverMonitor = StatusItemHoverMonitor()
    private let hoverTip = HoverTipWindow()
    private var hoverDelay: Timer?
    private var hoverSummary = HoverSummary.loading()
    private var hookRefreshTask: Task<Void, Never>?
    private var pendingRefresh: PendingRefresh = .none
    private var refreshObserver: NSObjectProtocol?
    private var hookObserver: NSObjectProtocol?

    init(client: any UsageFetching = UsageClient()) {
        self.client = client
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        configureHover()
        configureExternalRefresh()
        scheduleTimers()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        usageTimer?.invalidate()
        clockTimer?.invalidate()
        hoverDelay?.invalidate()
        hoverMonitor.stop()
        hoverTip.dismiss()
        hookRefreshTask?.cancel()
        if let refreshObserver {
            DistributedNotificationCenter.default().removeObserver(refreshObserver)
        }
        if let hookObserver {
            DistributedNotificationCenter.default().removeObserver(hookObserver)
        }
        stopClickMonitors()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: AppConfig.popoverWidth, height: 220)
        popover.contentViewController = popoverController
        popoverController.onRefresh = { [weak self] in self?.refresh() }
        popoverController.onContentSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        statusItem = item
        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = nil
        button.setAccessibilityLabel(AppConfig.appName)
        item.autosaveName = "com.hnl1.cursorquota.menubar"
        item.behavior = [.removalAllowed]
        UserDefaults.standard.set(10_000, forKey: "NSStatusItem Preferred Position com.hnl1.cursorquota.menubar")
        item.isVisible = true
        render(.loading)
        setHoverSummary(.loading())
    }

    private func configureHover() {
        hoverMonitor.buttonProvider = { [weak self] in self?.statusItem?.button }
        hoverMonitor.onChange = { [weak self] inside in
            self?.pointerMoved(inside: inside)
        }
        hoverMonitor.start()
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

    private func pointerMoved(inside: Bool) {
        if inside {
            guard hoverDelay == nil, !hoverTip.isVisible, !popover.isShown else { return }
            let timer = Timer(timeInterval: 0.28, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.presentHoverTip()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverDelay = timer
        } else {
            hoverDelay?.invalidate()
            hoverDelay = nil
            hoverTip.dismiss()
        }
    }

    private func presentHoverTip() {
        hoverDelay = nil
        guard !popover.isShown, let button = statusItem?.button else { return }
        guard StatusItemHoverMonitor.containsPointer(button) else { return }
        hoverTip.show(hoverSummary, from: button)
    }

    private func setHoverSummary(_ summary: HoverSummary) {
        hoverSummary = summary
        if hoverTip.isVisible {
            hoverTip.refresh(summary)
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

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        hoverDelay?.invalidate()
        hoverDelay = nil
        hoverTip.dismiss()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.highlight(true)
            startClickMonitors()
            makePopoverKey()
            refresh()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        makePopoverKey()
    }

    func popoverDidClose(_ notification: Notification) {
        stopClickMonitors()
        statusItem?.button?.highlight(false)
        if StatusItemHoverMonitor.containsPointer(statusItem?.button) {
            pointerMoved(inside: true)
        }
    }

    private func makePopoverKey() {
        guard let window = popover.contentViewController?.view.window else { return }
        if let panel = window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = false
        }
        window.makeKey()
        window.makeFirstResponder(nil)
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
        popoverController.showLoading()
        if report == nil {
            render(.loading)
            setHoverSummary(.loading())
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
        popoverController.updateClock(at: date)
        if let report {
            updateMenuBar(with: report, at: date, stale: staleMessage)
        }
    }

    private func apply(report: UsageReport) {
        self.report = report
        staleMessage = nil
        popoverController.show(report: report)
        updateMenuBar(with: report, stale: nil)
    }

    private func apply(error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? "无法读取 Cursor 用量。"
        let keepLast = (error as? QuotaError)?.keepsLastReading ?? true
        if keepLast, let report, report.hasActivePool() {
            staleMessage = message
            popoverController.show(report: report, staleMessage: message)
            updateMenuBar(with: report, stale: message)
        } else {
            showUnavailable(message)
        }
    }

    private func showUnavailable(_ message: String) {
        report = nil
        staleMessage = nil
        popoverController.showError(message)
        render(.unavailable)
        setHoverSummary(.unavailable(message))
        statusItem?.button?.setAccessibilityValue("用量不可用")
    }

    private func updateMenuBar(
        with report: UsageReport,
        at date: Date = Date(),
        stale: String?
    ) {
        let pool = report.headlinePool(at: date)
        let reading = pool.reading(at: date)
        render(.reading(reading, isStale: stale != nil))
        setHoverSummary(.make(report: report, stale: stale, at: date))
        statusItem?.button?.setAccessibilityValue(
            "\(pool.kind.shortTitle)剩余 \(reading.usageRemainingPercent)%，周期剩余 \(reading.timeRemainingPercent)%"
        )
    }

    private func render(_ scene: MenuBarScene) {
        guard let button = statusItem?.button else { return }
        let image = GaugeImage.image(for: scene)
        button.image = image
        switch scene {
        case .reading(let reading, _):
            button.title = "\(reading.usageRemainingPercent)%"
        case .loading:
            button.title = "…"
        case .unavailable:
            button.title = "—"
        }
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        statusItem?.isVisible = true
    }

    private func startClickMonitors() {
        guard localClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.popover.performClose(nil)
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }
}

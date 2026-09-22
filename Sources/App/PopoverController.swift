import AppKit

@MainActor
final class PopoverController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?
    var onLayoutChange: ((PanelLayout) -> Void)?
    var onShowsPercentChange: ((Bool) -> Void)?

    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Cursor 额度")
    private let errorLabel = NSTextField(labelWithString: "")
    private let planLabel = NSTextField(labelWithString: "")
    private let spendLabel = NSTextField(labelWithString: "")
    private let percentButton = HoverButton(title: "菜单栏 %", symbol: "checkmark", pointSize: 13)
    private let refreshButton = HoverButton(title: "--:--:--", symbol: "arrow.clockwise", pointSize: 13)
    private let restartButton = HoverButton(
        title: "重启",
        symbol: "arrow.triangle.2.circlepath",
        pointSize: 13,
        imageOnly: true
    )
    private let quitButton = HoverButton(title: "退出", symbol: "power", pointSize: 13, imageOnly: true)
    private let meters: [PoolKind: ComparisonMeter] = Dictionary(
        uniqueKeysWithValues: PoolKind.allCases.map { ($0, ComparisonMeter()) }
    )
    private var header: NSView!
    private var footer: NSView!
    private var report: UsageReport?
    private var layout = PanelLayout.default
    private var showsPercent = true
    private var refreshedAt: Date?
    private var clockAlert = false
    private var placeholderMessage = "正在读取 Cursor 用量…"
    private var dragKind: PoolKind?
    private var dragStartFrames: [PoolKind: NSRect] = [:]
    private var dragFromIndex = 0
    private var dragToIndex = 0

    override func loadView() {
        let root = MenuSurface(frame: NSRect(x: 0, y: 0, width: AppConfig.popoverWidth, height: 220))
        root.onAppearanceChange = { [weak self] in self?.styleChrome() }
        view = root
        configureLabels()
        header = makeHeader()
        footer = makeFooter()
        refreshButton.setSpinImage(Self.spinRingImage())

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: AppConfig.popoverWidth),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])

        showLoading()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nil)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        MenuTip.cancel()
    }

    func apply(layout: PanelLayout) {
        _ = view
        self.layout = layout
        refreshRows()
    }

    func apply(showsPercent: Bool) {
        _ = view
        self.showsPercent = showsPercent
        styleChrome()
    }

    func showLoading() {
        _ = view
        refreshButton.isEnabled = true
        setBusy(true)
        if report == nil {
            placeholderMessage = "正在读取 Cursor 用量…"
            replace(with: placeholderRows())
        }
    }

    func show(report: UsageReport, at date: Date = Date(), staleMessage: String? = nil) {
        _ = view
        self.report = report
        refreshButton.isEnabled = true
        setBusy(false)
        refreshedAt = date
        clockAlert = staleMessage != nil
        refreshButton.toolTip = staleMessage ?? "刷新"
        render(report: report, at: date)
    }

    func showError(_ message: String) {
        _ = view
        report = nil
        refreshButton.isEnabled = true
        setBusy(false)
        refreshedAt = nil
        clockAlert = true
        refreshButton.toolTip = message
        planLabel.stringValue = ""
        spendLabel.attributedStringValue = NSAttributedString()
        placeholderMessage = message
        styleChrome()
        replace(with: placeholderRows())
    }

    private func placeholderRows() -> [NSView] {
        [header, errorRow(placeholderMessage), footer]
    }

    /// 拉取中只转刷新图标，时间仍停在上次成功的时刻。
    private func setBusy(_ busy: Bool) {
        refreshButton.setSpinning(busy)
    }

    private func refreshRows() {
        if let report {
            render(report: report, at: Date())
        } else {
            replace(with: placeholderRows())
        }
    }

    func updateClock(at date: Date = Date()) {
        guard let report else { return }
        render(report: report, at: date)
    }

    private func render(report: UsageReport, at date: Date) {
        var planParts: [String] = []
        if let name = report.plan?.name, !name.isEmpty {
            planParts.append(name)
        }
        if let price = report.plan?.price, !price.isEmpty {
            planParts.append(price)
        }
        planLabel.stringValue = planParts.joined(separator: " · ")
        spendLabel.attributedStringValue = spendLine(report: report)
        styleChrome()

        var rows: [NSView] = [header]
        rows.append(contentsOf: meterRows(report: report, at: date))
        rows.append(footer)
        replace(with: rows)
    }

    private func spendLine(report: UsageReport) -> NSAttributedString {
        let line = NSMutableAttributedString()
        let quiet = Theme.secondaryText(view.effectiveAppearance)
        let primary = NSColor.labelColor
        let quietFont = NSFont.systemFont(ofSize: 11)
        let primaryFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        if let spend = report.spend, spend.hasLimit {
            line.append(NSAttributedString(
                string: "已用 \(Theme.currency(spend.includedDollars)) / \(Theme.currency(spend.limitDollars))",
                attributes: [.font: primaryFont, .foregroundColor: primary]
            ))
            line.append(NSAttributedString(
                string: " · ",
                attributes: [.font: quietFont, .foregroundColor: quiet]
            ))
        }
        line.append(NSAttributedString(
            string: Theme.footerReset(from: report.resetDate),
            attributes: [.font: quietFont, .foregroundColor: quiet]
        ))
        return line
    }

    /// 三条额度行常驻，顺序跟着配置走：勾选决定是否进菜单栏，没勾的置灰。
    private func meterRows(report: UsageReport, at date: Date) -> [NSView] {
        var rows: [NSView] = []
        for kind in layout.order {
            guard let meter = meters[kind] else { continue }
            meter.update(
                kind: kind,
                pool: report.pools.first { $0.kind == kind },
                inMenuBar: layout.isVisible(kind),
                canToggle: layout.canHide(kind) || !layout.isVisible(kind),
                at: date
            )
            meter.onToggle = { [weak self] in
                guard let self else { return }
                let visible = !self.layout.isVisible(kind)
                self.changeLayout { $0.setVisible(visible, for: kind) }
            }
            meter.onDrag = { [weak self] deltaY in
                self?.updateRowDrag(kind, deltaY: deltaY)
            }
            meter.onDragEnd = { [weak self] in
                self?.finishRowDrag(kind)
            }
            rows.append(meter)
        }
        return rows
    }

    private func updateRowDrag(_ kind: PoolKind, deltaY: CGFloat) {
        guard let frame = dragStartFrames[kind] ?? startRowDrag(kind) else { return }
        let order = layout.order
        let height = frame.height
        let minY = dragStartFrames.values.map(\.minY).min() ?? frame.minY
        let maxY = dragStartFrames.values.map(\.maxY).max() ?? frame.maxY
        let proposed = min(max(frame.minY + deltaY, minY), maxY - height)
        guard let meter = meters[kind] else { return }
        meter.frame.origin.y = proposed
        let visualMid = proposed + height / 2
        var target = 0
        for (index, item) in order.enumerated() where index != dragFromIndex {
            let mid = dragStartFrames[item]?.midY ?? visualMid
            if mid > visualMid { target += 1 }
        }
        dragToIndex = target
        for (index, item) in order.enumerated() {
            guard item != kind, let origin = dragStartFrames[item], let view = meters[item] else { continue }
            var shift: CGFloat = 0
            if dragToIndex > dragFromIndex, index > dragFromIndex, index <= dragToIndex {
                shift = height
            }
            if dragToIndex < dragFromIndex, index >= dragToIndex, index < dragFromIndex {
                shift = -height
            }
            view.frame.origin.y = origin.minY + shift
        }
    }

    private func startRowDrag(_ kind: PoolKind) -> NSRect? {
        dragKind = kind
        dragFromIndex = layout.order.firstIndex(of: kind) ?? 0
        dragToIndex = dragFromIndex
        dragStartFrames = Dictionary(uniqueKeysWithValues: layout.order.compactMap { item in
            guard let meter = meters[item] else { return nil }
            return (item, meter.frame)
        })
        return dragStartFrames[kind]
    }

    private func finishRowDrag(_ kind: PoolKind) {
        let steps = dragToIndex - dragFromIndex
        dragKind = nil
        dragStartFrames = [:]
        guard steps != 0 else {
            refreshRows()
            return
        }
        changeLayout { layout in
            let direction = steps > 0 ? 1 : -1
            for _ in 0..<abs(steps) {
                layout.move(kind, by: direction)
            }
        }
    }

    private func changeLayout(_ change: (inout PanelLayout) -> Void) {
        var updated = layout
        change(&updated)
        guard updated != layout else {
            refreshRows()
            return
        }
        layout = updated
        onLayoutChange?(updated)
        refreshRows()
    }

    private func configureLabels() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .labelColor
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        errorLabel.preferredMaxLayoutWidth = AppConfig.popoverWidth - 28
        planLabel.font = .systemFont(ofSize: 12, weight: .medium)
        planLabel.textColor = .labelColor
        spendLabel.font = .systemFont(ofSize: 11)
        configure(percentButton, action: #selector(percentTapped))
        configure(refreshButton, action: #selector(refreshTapped))
        configure(restartButton, action: #selector(restartTapped))
        configure(quitButton, action: #selector(quitTapped))
        refreshButton.toolTip = "刷新"
        restartButton.toolTip = "重启"
        quitButton.toolTip = "退出"
        styleChrome()
    }

    private func makeHeader() -> NSView {
        let spacer = flexibleSpacer()
        let row = NSStackView(views: [titleLabel, spacer, percentButton, refreshButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeFooter() -> NSView {
        let copy = NSStackView(views: [planLabel, spendLabel])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2
        let actions = NSStackView(views: [restartButton, quitButton])
        actions.orientation = .horizontal
        actions.alignment = .bottom
        actions.spacing = 2
        let row = NSStackView(views: [copy, flexibleSpacer(), actions])
        row.orientation = .horizontal
        row.alignment = .bottom
        row.spacing = 8
        return row
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func styleChrome() {
        let secondary = Theme.secondaryText(view.effectiveAppearance)
        let mark = showsPercent
            ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "菜单栏 %")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            : nil
        percentButton.image = mark ?? Self.emptyPercentMark
        percentButton.contentTintColor = secondary
        percentButton.attributedTitle = NSAttributedString(
            string: "菜单栏 %",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondary
            ]
        )
        let clock = refreshedAt.map(Theme.refreshClock(from:)) ?? (clockAlert ? "不可用" : "--:--:--")
        let clockColor = clockAlert ? NSColor.systemOrange : secondary
        refreshButton.contentTintColor = clockColor
        refreshButton.attributedTitle = NSAttributedString(
            string: clock,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: clockColor
            ]
        )
    }

    private static let emptyPercentMark: NSImage = {
        let image = NSImage(size: NSSize(width: 13, height: 13))
        image.isTemplate = true
        return image
    }()

    private static func spinRingImage() -> NSImage {
        let side: CGFloat = 13
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: side / 2, y: side / 2),
                radius: 4.15,
                startAngle: 40,
                endAngle: 320,
                clockwise: false
            )
            path.lineWidth = 1.1
            path.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func errorRow(_ message: String) -> NSView {
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        return errorLabel
    }

    private func configure(_ button: HoverButton, action: Selector) {
        button.target = self
        button.action = action
    }

    private func replace(with views: [NSView]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
        view.layoutSubtreeIfNeeded()
        let height = max(118, stack.fittingSize.height + 24)
        let size = NSSize(width: AppConfig.popoverWidth, height: height)
        preferredContentSize = size
        onContentSizeChange?(size)
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }

    @objc private func percentTapped() {
        showsPercent.toggle()
        styleChrome()
        onShowsPercentChange?(showsPercent)
    }

    @objc private func restartTapped() {
        view.enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.relaunch()
        }
    }

    /// 当前进程还在时，直接打开同一个包只会把现有实例调到前面。
    /// 先要求系统再起一份，成功后再退出这一份。
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { app, error in
            let launched = app != nil && error == nil
            Task { @MainActor in
                guard launched else { return }
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func quitTapped() {
        // 必须先收掉菜单：在菜单仍在跟踪时弹模态框，全屏空间的菜单栏会一直露在外面。
        view.enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.confirmQuit()
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出\(AppConfig.appName)？"
        alert.informativeText = "退出后菜单栏进度条会消失，重新打开应用才会再出现。"
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "退出")
        NSApp.activate(ignoringOtherApps: true)
        let shouldQuit = alert.runModal() == .alertSecondButtonReturn
        if shouldQuit {
            NSApp.terminate(nil)
        } else {
            NSApp.deactivate()
        }
    }
}

@MainActor
private final class HoverButton: NSButton {
    private var hovered = false
    private var baseImage: NSImage?
    private var idleImage: NSImage?
    private var spinImage: NSImage?
    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0

    convenience init(
        title: String,
        symbol: String,
        pointSize: CGFloat = 11,
        imageOnly: Bool = false
    ) {
        self.init(frame: .zero)
        self.title = imageOnly ? "" : title
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        symbolConfiguration = configuration
        image = symbolImage?.withSymbolConfiguration(configuration)
        baseImage = image
        idleImage = image
        imagePosition = imageOnly ? .imageOnly : .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        bezelStyle = .inline
        isBordered = false
        controlSize = .small
        refusesFirstResponder = true
        focusRingType = .none
        setAccessibilityLabel(title)
    }

    func setSpinImage(_ image: NSImage?) {
        spinImage = image
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        size.height += 6
        return size
    }

    /// 拉取期间让图标转起来。菜单跟踪时也要动，所以用 common 模式的定时器而不是动画。
    func setSpinning(_ spinning: Bool) {
        guard spinning != (spinTimer != nil) else { return }
        guard spinning else {
            spinTimer?.invalidate()
            spinTimer = nil
            spinAngle = 0
            baseImage = idleImage
            image = idleImage
            return
        }
        if let spinImage {
            baseImage = spinImage
            image = spinImage
        }
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceSpin() }
        }
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func advanceSpin() {
        spinAngle = (spinAngle + 24).truncatingRemainder(dividingBy: 360)
        image = rotated(baseImage, by: spinAngle)
    }

    private func rotated(_ source: NSImage?, by degrees: CGFloat) -> NSImage? {
        guard let source else { return nil }
        let result = NSImage(size: source.size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: -degrees)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            source.draw(in: rect)
            return true
        }
        result.isTemplate = source.isTemplate
        return result
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // 菜单窗口不是 key window，跟踪区必须用 activeAlways 才会收到进出事件。
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        syncHover()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func mouseDown(with event: NSEvent) {
        MenuTip.cancel()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 面板会整段重建，重建后鼠标可能已经压在按钮上，这里按真实指针位置校正一次。
    private func syncHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(point))
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsDisplay = true
        if value {
            MenuTip.schedule(from: self)
        } else {
            MenuTip.cancel(from: self)
        }
    }

    // 画在自己身上，不用 layer 背景色：菜单跟踪时会重绘这一行，layer 上的底色会被抹掉。
    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

/// 系统 tooltip 只在默认运行循环里出现，菜单跟踪时不会显示。
@MainActor
private enum MenuTip {
    private static var panel: NSWindow?
    private static var timer: Timer?
    private static weak var owner: NSView?

    static func schedule(from view: NSView) {
        cancel()
        guard let text = view.toolTip, !text.isEmpty else { return }
        owner = view
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak view] _ in
            Task { @MainActor in
                guard let view else { return }
                show(view.toolTip ?? "", from: view)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func cancel(from view: NSView? = nil) {
        if let view, owner != nil, owner !== view { return }
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        owner = nil
    }

    private static func show(_ text: String, from view: NSView) {
        guard view === owner, !text.isEmpty, let host = view.window else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 4
        label.preferredMaxLayoutWidth = 220
        let content = TipBackground()
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4)
        ])
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.contentView = content

        let button = host.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(
            x: button.midX - size.width / 2,
            y: button.minY - size.height - 4
        )
        if let screen = host.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y < visible.minY {
                origin.y = button.maxY + 4
            }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        panel = window
    }
}

@MainActor
private final class TipBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = dark
            ? NSColor.black.withAlphaComponent(0.88)
            : NSColor.white.withAlphaComponent(0.96)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

@MainActor
private final class MenuSurface: NSView {
    var onAppearanceChange: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

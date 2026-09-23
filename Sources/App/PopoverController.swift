import AppKit
import ServiceManagement

@MainActor
final class PopoverController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?
    var onLayoutChange: ((PanelLayout) -> Void)?
    var onShowsPercentChange: ((Bool) -> Void)?
    var onShowsUsedChange: ((Bool) -> Void)?

    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Cursor 额度")
    private let errorLabel = NSTextField(labelWithString: "")
    private let spendLabel = NSTextField(labelWithString: "")
    private let percentButton = HoverButton(title: "菜单栏%", symbol: "checkmark", pointSize: 13)
    private let usageButton = HoverButton(title: "展示已用", symbol: "checkmark", pointSize: 13)
    private let loginButton = HoverButton(title: "开机自启", symbol: "checkmark", pointSize: 13)
    private let refreshButton = HoverButton(title: "--:--:--", symbol: "arrow.clockwise", pointSize: 13)
    private let quitButton = HoverButton(title: "退出", symbol: "power", pointSize: 13, imageOnly: true)
    private let meters: [PoolKind: ComparisonMeter] = Dictionary(
        uniqueKeysWithValues: PoolKind.allCases.map { ($0, ComparisonMeter()) }
    )
    private var header: NSView!
    private var footer: NSView!
    private var edgePins: [NSLayoutConstraint] = []
    private var report: UsageReport?
    private var layout = PanelLayout.default
    private var showsPercent = false
    private var showsUsed = true
    private var loginHint = "登录后自动打开"
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

    func apply(showsUsed: Bool) {
        _ = view
        self.showsUsed = showsUsed
        styleChrome()
        refreshRows()
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
        titleLabel.stringValue = "Cursor 额度"
        spendLabel.stringValue = ""
        refreshFooterCopy()
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
        titleLabel.stringValue = titleText(report: report)
        spendLabel.stringValue = spendText(report: report)
        refreshFooterCopy()
        styleChrome()

        var rows: [NSView] = [header]
        rows.append(contentsOf: meterRows(report: report, at: date))
        rows.append(footer)
        replace(with: rows)
    }

    private func titleText(report: UsageReport) -> String {
        var parts: [String] = []
        if let name = report.plan?.name, !name.isEmpty {
            parts.append(name)
        }
        if let price = report.plan?.price, !price.isEmpty {
            parts.append(price)
        }
        return parts.isEmpty ? "Cursor 额度" : (["Cursor"] + parts).joined(separator: " · ")
    }

    private func spendText(report: UsageReport) -> String {
        guard let dollars = report.spend?.totalDollars else { return "" }
        return "已用 \(Theme.currency(dollars))"
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
                showsUsed: showsUsed,
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
        titleLabel.alignment = .left
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .labelColor
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        errorLabel.preferredMaxLayoutWidth = AppConfig.popoverWidth - 28
        spendLabel.font = .systemFont(ofSize: 11)
        spendLabel.alignment = .left
        spendLabel.setContentHuggingPriority(.required, for: .horizontal)
        configure(percentButton, action: #selector(percentTapped))
        configure(usageButton, action: #selector(usageTapped))
        usageButton.imagePosition = .noImage
        usageButton.image = nil
        configure(loginButton, action: #selector(loginTapped))
        percentButton.imagePosition = .imageTrailing
        loginButton.imagePosition = .imageTrailing
        configure(refreshButton, action: #selector(refreshTapped))
        configure(quitButton, action: #selector(quitTapped))
        refreshButton.toolTip = "刷新"
        quitButton.toolTip = "退出"
        styleChrome()
    }

    private func makeHeader() -> NSView {
        let spacer = flexibleSpacer()
        let spendRow = NSStackView(views: [spendLabel, spacer, refreshButton])
        spendRow.orientation = .horizontal
        spendRow.alignment = .centerY
        spendRow.spacing = 8
        spendRow.detachesHiddenViews = true
        let column = NSStackView(views: [titleLabel, spendRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            spendRow.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            spendRow.trailingAnchor.constraint(equalTo: column.trailingAnchor)
        ])
        alignTrailingContent(of: refreshButton, in: spendRow)
        return column
    }

    private func makeFooter() -> NSView {
        let switches = NSStackView(views: [usageButton, percentButton, loginButton])
        switches.orientation = .horizontal
        switches.alignment = .centerY
        switches.spacing = 2
        switches.clipsToBounds = false
        let controls = NSStackView(views: [switches, flexibleSpacer(), quitButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.clipsToBounds = false
        // 按钮文字比套餐行往右偏一个标题内边距。把这组开关拉回来，字的左缘才对齐。
        let align = switches.leadingAnchor.constraint(
            equalTo: controls.leadingAnchor,
            constant: -usageButton.titleLeadingInset
        )
        align.priority = .required
        align.isActive = true
        alignTrailingContent(of: quitButton, in: controls)
        refreshFooterCopy()
        return controls
    }

    /// 时间和退出图标比额度行的对勾更靠里，差的是按钮自己的内边距。
    /// 右内边距取负，按钮画出这一行，内容右缘才和勾对齐。
    private func alignTrailingContent(of button: HoverButton, in row: NSStackView) {
        row.clipsToBounds = false
        let overflow = button.contentTrailingInset - ComparisonMeter.markTrailingInset
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -overflow)
    }

    /// 菜单给这两栏的贴边优先级只有 250/260，打不过文字自己的宽度，栏会缩到内容那么窄并贴在右边。
    /// 每次重建都会把它们移出层级，上次的约束会失效，所以要重新钉上。
    private func pinFullWidthBars() {
        NSLayoutConstraint.deactivate(edgePins)
        edgePins = [header, footer].flatMap { bar in
            [
                bar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
            ]
        }
        NSLayoutConstraint.activate(edgePins)
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func refreshFooterCopy() {
        spendLabel.isHidden = spendLabel.stringValue.isEmpty
    }

    private func styleChrome() {
        let secondary = Theme.secondaryText(view.effectiveAppearance)
        spendLabel.textColor = secondary
        styleToggle(percentButton, title: "菜单栏%", on: showsPercent)
        styleUsageButton()
        styleToggle(loginButton, title: "开机自启", on: LoginItem.isEnabled)
        loginButton.toolTip = loginHint
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

    private func styleUsageButton() {
        let title = showsUsed ? "展示已用" : "展示剩余"
        let secondary = Theme.secondaryText(view.effectiveAppearance)
        usageButton.image = nil
        usageButton.imagePosition = .noImage
        usageButton.contentTintColor = secondary
        usageButton.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondary
            ]
        )
        usageButton.setAccessibilityLabel(title)
    }

    private func styleToggle(_ button: HoverButton, title: String, on: Bool) {
        let secondary = Theme.secondaryText(view.effectiveAppearance)
        button.image = on ? Self.toggleMarkOn : Self.toggleMarkOff
        button.contentTintColor = secondary
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondary
            ]
        )
    }

    /// 勾选和空白必须是同一块普通图。系统符号按对齐矩形排版，空白图按整张尺寸排，
    /// 两种状态的按钮边界会差一截，悬停底就跟着变大变小。
    private static let toggleMarkOn = toggleMark(drawn: true)
    private static let toggleMarkOff = toggleMark(drawn: false)

    private static func toggleMark(drawn: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbol = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let size = symbol?.size ?? NSSize(width: 13, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            if drawn {
                symbol?.draw(in: rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

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
        pinFullWidthBars()
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

    @objc private func usageTapped() {
        showsUsed.toggle()
        styleChrome()
        refreshRows()
        onShowsUsedChange?(showsUsed)
    }

    @objc private func loginTapped() {
        let turningOn = !LoginItem.isEnabled
        switch LoginItem.setEnabled(turningOn) {
        case .enabled:
            loginHint = "登录后自动打开"
        case .disabled:
            loginHint = "登录后自动打开"
        case .needsApproval:
            loginHint = "需要在系统设置的登录项里允许"
            styleChrome()
            view.enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        case .failed:
            loginHint = "暂时无法设置开机自启"
        }
        styleChrome()
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

    /// 标题左缘相对按钮边界的距离。用来和上面的文字左对齐。
    var titleLeadingInset: CGFloat {
        guard let cell = cell as? NSButtonCell else { return 0 }
        let size = intrinsicContentSize
        guard size.width > 1, size.height > 1 else { return 0 }
        return cell.titleRect(forBounds: NSRect(origin: .zero, size: size)).minX
    }

    /// 字或图标右缘，相对对齐矩形右缘的内缩。布局钉的是对齐矩形，不是按钮外框。
    var contentTrailingInset: CGFloat {
        guard let cell = cell as? NSButtonCell else { return 0 }
        let size = intrinsicContentSize
        guard size.width > 1, size.height > 1 else { return 0 }
        let bounds = NSRect(origin: .zero, size: size)
        let content = imagePosition == .imageOnly || title.isEmpty
            ? cell.imageRect(forBounds: bounds)
            : cell.titleRect(forBounds: bounds)
        return size.width - alignmentRectInsets.right - content.maxX
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

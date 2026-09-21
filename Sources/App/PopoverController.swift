import AppKit

@MainActor
final class PopoverController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?
    var onLayoutChange: ((PanelLayout) -> Void)?

    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: AppConfig.popoverTitle)
    private let statusLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let planLabel = NSTextField(labelWithString: "")
    private let spendLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let refreshButton = HoverButton(title: "刷新", symbol: "arrow.clockwise")
    private let quitButton = HoverButton(title: "退出", symbol: "power")
    private let hint = NSTextField(labelWithString: "勾选的显示在菜单栏，箭头调整顺序")
    private let meters: [PoolKind: ComparisonMeter] = Dictionary(
        uniqueKeysWithValues: PoolKind.allCases.map { ($0, ComparisonMeter()) }
    )
    private let dividers = (1..<PoolKind.allCases.count).map { _ in Divider() }

    private var header: NSView!
    private var footer: NSView!
    private var meta: NSView!
    private var report: UsageReport?
    private var layout = PanelLayout.default
    private var placeholderMessage = "正在读取 Cursor 用量…"
    private var busyTimer: Timer?
    private var busyDots = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: AppConfig.popoverWidth, height: 220))
        view = root
        configureLabels()
        header = makeHeader()
        meta = makeMeta()
        footer = makeFooter()

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

    func apply(layout: PanelLayout) {
        _ = view
        self.layout = layout
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
        statusLabel.stringValue = staleMessage == nil ? Theme.refreshText(from: date) : "过期"
        statusLabel.textColor = staleMessage == nil ? .secondaryLabelColor : .systemOrange
        statusLabel.toolTip = staleMessage
        render(report: report, at: date)
    }

    func showError(_ message: String) {
        _ = view
        report = nil
        refreshButton.isEnabled = true
        setBusy(false)
        statusLabel.stringValue = "不可用"
        statusLabel.textColor = .systemOrange
        statusLabel.toolTip = message
        resetLabel.stringValue = ""
        planLabel.stringValue = ""
        spendLabel.stringValue = ""
        placeholderMessage = message
        replace(with: placeholderRows())
    }

    private func placeholderRows() -> [NSView] {
        [header, errorRow(placeholderMessage), footer]
    }

    /// 拉取中：刷新图标转圈，右上角「更新中」后面的点循环。
    private func setBusy(_ busy: Bool) {
        refreshButton.setSpinning(busy)
        busyTimer?.invalidate()
        busyTimer = nil
        guard busy else { return }
        busyDots = 0
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "更新中"
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceBusyDots() }
        }
        RunLoop.main.add(timer, forMode: .common)
        busyTimer = timer
    }

    private func advanceBusyDots() {
        busyDots = (busyDots + 1) % 4
        statusLabel.stringValue = "更新中" + String(repeating: ".", count: busyDots)
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

        if let spend = report.spend, spend.hasLimit {
            spendLabel.stringValue =
                "已用 \(Theme.currency(spend.includedDollars)) / \(Theme.currency(spend.limitDollars))"
        } else {
            spendLabel.stringValue = ""
        }
        resetLabel.stringValue = Theme.resetText(from: report.resetDate)

        var rows: [NSView] = [header, hint]
        rows.append(contentsOf: meterRows(report: report, at: date))
        rows.append(meta)
        rows.append(footer)
        replace(with: rows)
    }

    /// 三条额度行常驻，顺序跟着配置走：勾选决定是否进菜单栏，没勾的置灰。
    private func meterRows(report: UsageReport, at date: Date) -> [NSView] {
        var rows: [NSView] = []
        for (index, kind) in layout.order.enumerated() {
            guard let meter = meters[kind] else { continue }
            meter.update(
                kind: kind,
                pool: report.pools.first { $0.kind == kind },
                inMenuBar: layout.isVisible(kind),
                canToggle: layout.canHide(kind),
                canMoveUp: layout.canMove(kind, by: -1),
                canMoveDown: layout.canMove(kind, by: 1),
                at: date
            )
            meter.onToggle = { [weak self] isOn in
                self?.changeLayout { $0.setVisible(isOn, for: kind) }
            }
            meter.onMove = { [weak self] offset in
                self?.changeLayout { $0.move(kind, by: offset) }
            }
            if index > 0, dividers.indices.contains(index - 1) {
                rows.append(dividers[index - 1])
            }
            rows.append(meter)
        }
        return rows
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
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .labelColor
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        errorLabel.preferredMaxLayoutWidth = AppConfig.popoverWidth - 28
        planLabel.font = .systemFont(ofSize: 11, weight: .medium)
        planLabel.textColor = .labelColor
        spendLabel.font = .systemFont(ofSize: 11, weight: .medium)
        spendLabel.textColor = .labelColor
        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor
        configure(refreshButton, action: #selector(refreshTapped))
        configure(quitButton, action: #selector(quitTapped))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
    }

    private func makeHeader() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)
        row.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            )
        ])
        return row
    }

    private func makeMeta() -> NSView {
        let column = NSStackView(views: [planLabel, spendLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        return column
    }

    private func makeFooter() -> NSView {
        let row = NSStackView(views: [resetLabel, NSView(), refreshButton, quitButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
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
    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0

    convenience init(title: String, symbol: String) {
        self.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        baseImage = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        )
        imagePosition = .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        bezelStyle = .inline
        isBordered = false
        controlSize = .small
        refusesFirstResponder = true
        focusRingType = .none
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
            image = baseImage
            return
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

@MainActor
private final class Divider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 8).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let y = bounds.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: y))
        path.line(to: NSPoint(x: bounds.maxX, y: y))
        path.lineWidth = 1
        path.stroke()
    }
}

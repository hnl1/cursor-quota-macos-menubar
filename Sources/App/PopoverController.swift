import AppKit

@MainActor
final class PopoverController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?

    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: AppConfig.popoverTitle)
    private let statusLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let planLabel = NSTextField(labelWithString: "")
    private let spendLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let refreshButton = HoverButton(title: "刷新", symbol: "arrow.clockwise")
    private let quitButton = HoverButton(title: "退出", symbol: "power")
    private let cursorMeter = ComparisonMeter()
    private let apiMeter = ComparisonMeter()
    private let grokMeter = ComparisonMeter()
    private let divider = Divider()
    private let grokDivider = Divider()

    private var header: NSView!
    private var footer: NSView!
    private var meta: NSView!
    private var report: UsageReport?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: AppConfig.popoverWidth, height: 220))
        root.translatesAutoresizingMaskIntoConstraints = false
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

    func showLoading() {
        _ = view
        refreshButton.isEnabled = true
        statusLabel.stringValue = "更新中"
        if report == nil {
            replace(with: [header, errorRow("正在读取 Cursor 用量…"), footer])
        }
    }

    func show(report: UsageReport, at date: Date = Date(), staleMessage: String? = nil) {
        _ = view
        self.report = report
        refreshButton.isEnabled = true
        statusLabel.stringValue = staleMessage == nil ? "实时" : "过期"
        statusLabel.textColor = staleMessage == nil ? .tertiaryLabelColor : .systemOrange
        statusLabel.toolTip = staleMessage
        render(report: report, at: date)
    }

    func showError(_ message: String) {
        _ = view
        report = nil
        refreshButton.isEnabled = true
        statusLabel.stringValue = "不可用"
        statusLabel.textColor = .systemOrange
        statusLabel.toolTip = message
        resetLabel.stringValue = ""
        planLabel.stringValue = ""
        spendLabel.stringValue = ""
        replace(with: [header, errorRow(message), footer])
    }

    func updateClock(at date: Date = Date()) {
        guard let report else { return }
        render(report: report, at: date)
    }

    private func render(report: UsageReport, at date: Date) {
        let cursor = report.pools.first(where: { $0.kind == .cursorModels })
        let api = report.pools.first(where: { $0.kind == .apiModels })
        let grok = report.pools.first(where: { $0.kind == .grokBot })

        if let cursor {
            cursorMeter.update(pool: cursor, at: date)
        } else {
            cursorMeter.showUnavailable(title: PoolKind.cursorModels.title)
        }
        if let api {
            apiMeter.update(pool: api, at: date)
        } else {
            apiMeter.showUnavailable(title: PoolKind.apiModels.title)
        }
        if let grok {
            grokMeter.update(pool: grok, at: date)
        }

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

        var rows: [NSView] = [header]
        if cursor != nil { rows.append(cursorMeter) }
        if cursor != nil, api != nil { rows.append(divider) }
        if api != nil { rows.append(apiMeter) }
        if grok != nil {
            if cursor != nil || api != nil { rows.append(grokDivider) }
            rows.append(grokMeter)
        }
        rows.append(meta)
        rows.append(footer)
        replace(with: rows)
    }

    private func configureLabels() {
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        errorLabel.preferredMaxLayoutWidth = AppConfig.popoverWidth - 28
        planLabel.font = .systemFont(ofSize: 11, weight: .medium)
        planLabel.textColor = .secondaryLabelColor
        spendLabel.font = .systemFont(ofSize: 11, weight: .medium)
        spendLabel.textColor = .secondaryLabelColor
        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .tertiaryLabelColor
        configure(refreshButton, action: #selector(refreshTapped))
        configure(quitButton, action: #selector(quitTapped))
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
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出\(AppConfig.appName)？"
        alert.informativeText = "退出后菜单栏进度条会消失，重新打开应用才会再出现。"
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "退出")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

@MainActor
private final class HoverButton: NSButton {
    private var hovered = false

    convenience init(title: String, symbol: String) {
        self.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        imagePosition = .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        bezelStyle = .inline
        isBordered = false
        controlSize = .small
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        size.height += 6
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        applyHover()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        applyHover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyHover()
    }

    private func applyHover() {
        layer?.backgroundColor = hovered
            ? NSColor.labelColor.withAlphaComponent(0.12).cgColor
            : nil
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

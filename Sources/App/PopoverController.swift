import AppKit
import ServiceManagement

enum PanelMetrics {
    /// 灰底列到可见内容的左右距离。
    static let contentInset: CGFloat = 6
}

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
    private let percentButton = HoverButton(title: "菜单栏%")
    private let usageButton = HoverButton(title: "展示已用")
    private let loginButton = HoverButton(title: "开机自启")
    private let refreshButton = HoverButton(title: "--:--:--", image: PopoverController.refreshImage)
    private let quitButton = HoverButton(title: "退出", image: PopoverController.powerImage, imageOnly: true)
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
        configure(loginButton, action: #selector(loginTapped))
        prepareIconButton(usageButton)
        prepareIconButton(percentButton)
        prepareIconButton(loginButton)
        configure(refreshButton, action: #selector(refreshTapped))
        configure(quitButton, action: #selector(quitTapped))
        refreshButton.toolTip = "刷新"
        quitButton.toolTip = "退出"
        styleChrome()
    }

    private func makeHeader() -> NSView {
        let row = NSStackView(views: [titleLabel, flexibleSpacer(), spendLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.detachesHiddenViews = true
        // 栈按对齐矩形排文字，字形画在框的外缘。把对齐矩形再让出这段，字形才落在内容线上。
        row.edgeInsets = NSEdgeInsets(
            top: 0,
            left: PanelMetrics.contentInset + titleLabel.alignmentRectInsets.left,
            bottom: 0,
            right: PanelMetrics.contentInset + spendLabel.alignmentRectInsets.right
        )
        return row
    }

    private func makeFooter() -> NSView {
        let switches = NSStackView(views: [usageButton, percentButton, loginButton, quitButton])
        switches.orientation = .horizontal
        switches.alignment = .centerY
        switches.spacing = 2
        let controls = NSStackView(views: [refreshButton, flexibleSpacer(), switches])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        refreshFooterCopy()
        return controls
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
        stylePercentButton()
        styleUsageButton()
        styleLoginButton()
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
        let label = showsUsed ? "展示已用" : "展示剩余"
        usageButton.image = showsUsed ? Self.usedImage : Self.remainingImage
        usageButton.contentTintColor = Theme.secondaryText(view.effectiveAppearance)
        usageButton.toolTip = label
        usageButton.setAccessibilityLabel(label)
    }

    private func prepareIconButton(_ button: HoverButton) {
        button.imagePosition = .imageOnly
        button.title = ""
    }

    private func stylePercentButton() {
        let on = showsPercent
        let label = on ? "菜单栏显示百分比" : "菜单栏不显示百分比"
        percentButton.image = on ? Self.percentOnImage : Self.percentOffImage
        percentButton.contentTintColor = Theme.secondaryText(view.effectiveAppearance)
        percentButton.toolTip = label
        percentButton.setAccessibilityLabel(label)
    }

    private func styleLoginButton() {
        let on = LoginItem.isEnabled
        let label = loginHint == "登录后自动打开"
            ? (on ? "开机自启：登录后自动打开" : "开机自启已关闭")
            : loginHint
        loginButton.image = on ? Self.plugOnImage : Self.plugOffImage
        loginButton.contentTintColor = Theme.secondaryText(view.effectiveAppearance)
        loginButton.toolTip = label
        loginButton.setAccessibilityLabel(label)
    }

    /// 两种状态用同一张画布，按钮边界才不会跟着图标变。
    private static let percentOnImage = iconImage { percentMark(in: $0) }
    private static let percentOffImage = iconImage { ringMark(in: $0) }
    private static let plugOnImage = iconImage(flipped: true) { drawPlug(in: $0, slashed: false) }
    private static let plugOffImage = iconImage(flipped: true) { drawPlug(in: $0, slashed: true) }
    private static let usedImage = iconImage { usageRing(in: $0, showsUsed: true) }
    private static let remainingImage = iconImage { usageRing(in: $0, showsUsed: false) }
    private static let refreshImage = iconImage { drawRefresh(in: $0) }
    private static let powerImage = iconImage { drawPower(in: $0) }

    private static let usageRingRadius: CGFloat = 5.1
    private static let usageRingWidth: CGFloat = 2.2

    private static func iconImage(flipped: Bool = false, _ draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: flipped) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func percentMark(in rect: NSRect) {
        let text = "%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2 - 0.4
            ),
            withAttributes: attributes
        )
    }

    private static func ringMark(in rect: NSRect) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: 4.87,
            startAngle: 0,
            endAngle: 360
        )
        path.lineWidth = 1.8
        NSColor.black.setStroke()
        path.stroke()
    }

    /// 和面板圆环同一种读法：深色弧从 12 点顺时针画到交界。
    /// 已用：深色箭头在交界处朝顺时针，深色在长；剩余：灰色箭头朝逆时针，灰色在长、深色在缩。
    private static func usageRing(in rect: NSRect, showsUsed: Bool) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let boundary: CGFloat = showsUsed ? 0.25 : 0.75
        let trackAlpha: CGFloat = 0.26
        func arc(from start: CGFloat, to end: CGFloat) {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: usageRingRadius,
                startAngle: 90 - 360 * start,
                endAngle: 90 - 360 * end,
                clockwise: true
            )
            path.lineWidth = usageRingWidth
            path.stroke()
        }
        let head = usageArrowHead(center: center, at: boundary, clockwise: showsUsed)
        NSColor.black.set()
        if showsUsed {
            NSColor.black.withAlphaComponent(trackAlpha).setStroke()
            arc(from: 0, to: 1)
            NSColor.black.set()
            arc(from: 0, to: boundary)
            head.fill()
            head.stroke()
            return
        }
        arc(from: 0, to: boundary)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        head.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        // 轨道和箭头在同一透明层里画成实色再整体变淡，重叠处不会加深。
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setAlpha(trackAlpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        arc(from: boundary, to: 1)
        head.fill()
        context.endTransparencyLayer()
        context.setAlpha(1)
    }

    /// 底边中点落在圆环上 fraction 处，尖端沿切线伸出。
    private static func usageArrowHead(center: NSPoint, at fraction: CGFloat, clockwise: Bool) -> NSBezierPath {
        let length: CGFloat = 3.0
        let halfWidth: CGFloat = 2.6
        let angle = (90 - 360 * fraction) * .pi / 180
        let normal = NSPoint(x: cos(angle), y: sin(angle))
        let direction: CGFloat = clockwise ? 1 : -1
        let tangent = NSPoint(x: sin(angle) * direction, y: -cos(angle) * direction)
        let base = NSPoint(x: center.x + usageRingRadius * normal.x, y: center.y + usageRingRadius * normal.y)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: base.x + tangent.x * length, y: base.y + tangent.y * length))
        path.line(to: NSPoint(x: base.x + normal.x * halfWidth, y: base.y + normal.y * halfWidth))
        path.line(to: NSPoint(x: base.x - normal.x * halfWidth, y: base.y - normal.y * halfWidth))
        path.close()
        path.lineWidth = 0.5
        path.lineJoinStyle = .round
        return path
    }

    private static func drawPlug(in rect: NSRect, slashed: Bool) {
        let scale = rect.width / 24
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
        }
        NSColor.black.set()
        NSBezierPath(roundedRect: box(7.15, 2.05, 2.45, 4.7), xRadius: 0.7 * scale, yRadius: 0.7 * scale).fill()
        NSBezierPath(roundedRect: box(14.4, 2.05, 2.45, 4.7), xRadius: 0.7 * scale, yRadius: 0.7 * scale).fill()
        let body = NSBezierPath(
            roundedRect: box(5.25, 6.15, 13.5, 10.15),
            xRadius: 2.45 * scale,
            yRadius: 2.45 * scale
        )
        body.lineWidth = 1.9 * scale
        body.stroke()
        let cord = NSBezierPath()
        cord.move(to: NSPoint(x: 12 * scale, y: 16.3 * scale))
        cord.line(to: NSPoint(x: 12 * scale, y: 21.15 * scale))
        cord.lineWidth = 1.9 * scale
        cord.lineCapStyle = .round
        cord.stroke()
        guard slashed else { return }
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 4.7 * scale, y: 19.3 * scale))
        slash.line(to: NSPoint(x: 19.3 * scale, y: 4.7 * scale))
        slash.lineCapStyle = .round
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        slash.lineWidth = 3.6 * scale
        slash.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setStroke()
        slash.lineWidth = 1.85 * scale
        slash.stroke()
    }

    private static func drawRefresh(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 4.85
        let lineWidth: CGFloat = 1.8
        // 顺时针约 250°，缺口朝右；箭头落在缺口上沿。
        let endAngle: CGFloat = 55
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: -55,
            endAngle: endAngle,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor.black.set()
        arc.stroke()

        let theta = endAngle * .pi / 180
        let radial = NSPoint(x: cos(theta), y: sin(theta))
        let tangent = NSPoint(x: sin(theta), y: -cos(theta))
        let base = NSPoint(x: center.x + radius * radial.x, y: center.y + radius * radial.y)
        let length: CGFloat = 3.1
        let half: CGFloat = 2.35
        let head = NSBezierPath()
        head.move(to: NSPoint(x: base.x + tangent.x * length, y: base.y + tangent.y * length))
        head.line(to: NSPoint(x: base.x + radial.x * half, y: base.y + radial.y * half))
        head.line(to: NSPoint(x: base.x - radial.x * half, y: base.y - radial.y * half))
        head.close()
        head.fill()
    }

    private static func drawPower(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY - 0.35)
        let radius: CGFloat = 4.7
        let lineWidth: CGFloat = 1.8
        NSColor.black.set()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: center.x, y: center.y + 1.0))
        stem.line(to: NSPoint(x: center.x, y: center.y + 6.1))
        stem.lineWidth = lineWidth
        stem.lineCapStyle = .round
        stem.stroke()
        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 130,
            endAngle: 50,
            clockwise: false
        )
        ring.lineWidth = lineWidth
        ring.lineCapStyle = .round
        ring.stroke()
    }

    private static func spinRingImage() -> NSImage {
        iconImage { rect in
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: 4.85,
                startAngle: 40,
                endAngle: 320,
                clockwise: false
            )
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
        }
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
        var previous: NSView?
        for view in views {
            stack.addArrangedSubview(view)
            if let previous, previous is ComparisonMeter, view is ComparisonMeter {
                stack.setCustomSpacing(4, after: previous)
            }
            previous = view
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

/// 左右内距由这里定，不用系统按钮把多余宽度摊到一侧。
private final class HoverButtonCell: NSButtonCell {
    /// 系统 `imageHugsTitle` 量出来的图标和文字间距。
    private static let imageTitleGap: CGFloat = 2
    private static let verticalExtra: CGFloat = 6

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let size = image.size
        return NSRect(
            x: rect.minX + PanelMetrics.contentInset,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let titleSize = Self.titleSize(of: self)
        guard titleSize.width > 0, titleSize.height > 0 else { return .zero }
        let imageFrame = imageRect(forBounds: rect)
        let x = imageFrame.width > 0
            ? imageFrame.maxX + Self.imageTitleGap
            : rect.minX + PanelMetrics.contentInset
        return NSRect(
            x: x,
            y: rect.midY - titleSize.height / 2,
            width: titleSize.width,
            height: titleSize.height
        )
    }

    func fittingSize() -> NSSize {
        let imageSize = image?.size ?? .zero
        let titleSize = Self.titleSize(of: self)
        let gap = imageSize.width > 0 && titleSize.width > 0 ? Self.imageTitleGap : 0
        let contentWidth = imageSize.width + gap + titleSize.width
        let contentHeight = max(imageSize.height, titleSize.height)
        return NSSize(
            width: contentWidth + PanelMetrics.contentInset * 2,
            height: contentHeight + Self.verticalExtra
        )
    }

    private static func titleSize(of cell: NSButtonCell) -> NSSize {
        if cell.attributedTitle.length > 0 {
            return cell.attributedTitle.size()
        }
        guard !cell.title.isEmpty else { return .zero }
        let font = cell.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return cell.title.size(withAttributes: [.font: font])
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
        image: NSImage? = nil,
        imageOnly: Bool = false
    ) {
        self.init(frame: .zero)
        cell = HoverButtonCell(textCell: "")
        self.title = imageOnly ? "" : title
        self.image = image
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
        (cell as? HoverButtonCell)?.fittingSize() ?? super.intrinsicContentSize
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
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        // 系统默认按指针在区外登记，重建时指针若已压在上面，滑出时收不到 mouseExited，高亮会卡住。
        if pointerInside {
            options.insert(.assumeInside)
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
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
        updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var pointerInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// 面板会整段重建，重建后鼠标可能已经压在按钮上，这里按真实指针位置校正一次。
    private func syncHover() {
        guard window != nil else { return }
        setHovered(pointerInside)
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

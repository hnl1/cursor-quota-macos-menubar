import AppKit

/// 面板里的一条额度：圆环 + 名称 + 剩余百分比，行首勾选是否进菜单栏，行尾箭头调顺序。
@MainActor
final class ComparisonMeter: NSView {
    var onToggle: ((Bool) -> Void)?
    var onMove: ((Int) -> Void)?

    private let include = NSButton()
    private let up = SquareButton()
    private let down = SquareButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "—")
    private let timeTitle = NSTextField(labelWithString: "周期剩余")
    private let timeLabel = NSTextField(labelWithString: "—")

    private var usageFraction = 0.0
    private var timeFraction = 0.0
    private var fillColor = NSColor.systemGray
    private var showsValue = false
    private var ringRect = NSRect.zero

    private static let ringSize: CGFloat = 44
    private static let rowHeight: CGFloat = 52
    /// 行尾那一列：上箭头 / 勾选框 / 下箭头
    private static let controlWidth: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        usageLabel.alignment = .right
        timeTitle.font = .systemFont(ofSize: 11, weight: .medium)
        timeTitle.textColor = .labelColor
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = .labelColor
        timeLabel.alignment = .right

        include.setButtonType(.switch)
        include.title = ""
        include.target = self
        include.action = #selector(toggled)
        include.refusesFirstResponder = true
        include.focusRingType = .none

        configure(up, symbol: "chevron.up", action: #selector(moveUpTapped))
        configure(down, symbol: "chevron.down", action: #selector(moveDownTapped))

        for label in [titleLabel, usageLabel, timeTitle, timeLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        for button in [include, up, down] {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        let textLeading = Self.ringSize + 10
        let textTrailing = -(Self.controlWidth + 8)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),

            include.trailingAnchor.constraint(equalTo: trailingAnchor),
            include.centerYAnchor.constraint(equalTo: centerYAnchor),
            up.centerXAnchor.constraint(equalTo: include.centerXAnchor),
            up.bottomAnchor.constraint(equalTo: include.topAnchor, constant: -1),
            down.centerXAnchor.constraint(equalTo: include.centerXAnchor),
            down.topAnchor.constraint(equalTo: include.bottomAnchor, constant: 1),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            usageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: textTrailing),
            usageLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            usageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            timeTitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeTitle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: textTrailing),
            timeLabel.centerYAnchor.constraint(equalTo: timeTitle.centerYAnchor),
            timeLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: timeTitle.trailingAnchor,
                constant: 8
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.rowHeight)
    }

    override func layout() {
        super.layout()
        let y = bounds.midY - Self.ringSize / 2
        ringRect = NSRect(x: bounds.minX, y: y, width: Self.ringSize, height: Self.ringSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        RingGauge.draw(
            in: ringRect,
            usageRemaining: usageFraction,
            timeRemaining: timeFraction,
            color: fillColor,
            track: Theme.trackFill(appearance: effectiveAppearance),
            lineWidth: 5,
            showsValue: showsValue,
            tickWidth: 0.7
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func update(
        kind: PoolKind,
        pool: UsagePool?,
        inMenuBar: Bool,
        canToggle: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool,
        at date: Date
    ) {
        include.state = inMenuBar ? .on : .off
        include.isEnabled = canToggle
        include.setAccessibilityLabel("在菜单栏显示\(kind.shortTitle)")
        setEnabled(up, canMoveUp, label: "上移\(kind.shortTitle)")
        setEnabled(down, canMoveDown, label: "下移\(kind.shortTitle)")
        titleLabel.stringValue = kind.title
        timeTitle.stringValue = kind.timeTitle

        guard let pool else {
            showUnavailable(kind: kind)
            return
        }
        let reading = pool.reading(at: date)
        showsValue = true
        usageFraction = reading.usageRemainingFraction
        timeFraction = reading.timeRemainingFraction
        // 勾选只决定是否上菜单栏，面板里三条都照常显示。
        fillColor = Theme.paceColor(reading.pace)
        usageLabel.stringValue = "\(reading.usageRemainingPercent)%"
        usageLabel.textColor = fillColor
        titleLabel.textColor = .labelColor
        timeLabel.stringValue = "\(reading.timeRemainingPercent)%"
        setAccessibilityLabel(kind.title)
        setAccessibilityValue(
            "剩余 \(reading.usageRemainingPercent)%，\(kind.timeTitle) \(reading.timeRemainingPercent)%"
                + (inMenuBar ? "，在菜单栏显示" : "，未在菜单栏显示")
        )
        needsLayout = true
        needsDisplay = true
    }

    private func showUnavailable(kind: PoolKind) {
        showsValue = false
        usageFraction = 0
        timeFraction = 0
        fillColor = .systemGray
        titleLabel.textColor = .secondaryLabelColor
        usageLabel.stringValue = "—"
        usageLabel.textColor = .tertiaryLabelColor
        timeLabel.stringValue = "—"
        setAccessibilityLabel(kind.title)
        setAccessibilityValue("暂无数据")
        needsDisplay = true
    }

    private func configure(_ button: SquareButton, symbol: String, action: Selector) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.controlSize = .small
        button.target = self
        button.action = action
        button.refusesFirstResponder = true
        button.focusRingType = .none
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.controlWidth - 2),
            button.heightAnchor.constraint(equalToConstant: Self.controlWidth - 2)
        ])
    }

    private func setEnabled(_ button: SquareButton, _ enabled: Bool, label: String) {
        button.isEnabled = enabled
        button.contentTintColor = enabled ? .labelColor : .tertiaryLabelColor
        button.setAccessibilityLabel(label)
        button.needsDisplay = true
    }

    @objc private func toggled() {
        onToggle?(include.state == .on)
    }

    @objc private func moveUpTapped() {
        onMove?(-1)
    }

    @objc private func moveDownTapped() {
        onMove?(1)
    }
}

/// 和勾选框同尺寸的小方按钮：圆角底 + 描边，悬停加深。
@MainActor
private final class SquareButton: NSButton {
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
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

    private func syncHover() {
        guard let window else { return }
        setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value, isEnabled else { return }
        hovered = value
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        let fill = isEnabled
            ? NSColor.labelColor.withAlphaComponent(hovered ? 0.22 : 0.1)
            : NSColor.labelColor.withAlphaComponent(0.04)
        fill.setFill()
        box.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.28 : 0.12).setStroke()
        box.lineWidth = 1
        box.stroke()
        super.draw(dirtyRect)
    }
}

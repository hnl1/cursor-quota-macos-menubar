import AppKit

/// 面板里的一条额度。单击整行切换是否出现在菜单栏，按住拖动调整顺序。
@MainActor
final class ComparisonMeter: NSView {
    var onToggle: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "—")
    private let timeTitle = NSTextField(labelWithString: "（月）周期已过")
    private let timeLabel = NSTextField(labelWithString: "—")
    private let resetLabel = NSTextField(labelWithString: "")
    private let mark = NSImageView()

    private var usageFraction = 0.0
    private var timeFraction = 0.0
    private var fillColor = NSColor.systemGray
    private var showsValue = false
    private var showsUsed = true
    private var ringRect = NSRect.zero
    private var hovered = false
    private var lifted = false
    private var canToggle = true
    private var kindTitle = ""

    private static let ringSize: CGFloat = 44
    private static let rowHeight: CGFloat = 62
    private static let markSide: CGFloat = 22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        usageLabel.alignment = .right
        timeTitle.font = .systemFont(ofSize: 11, weight: .regular)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.alignment = .right
        resetLabel.font = .systemFont(ofSize: 11, weight: .regular)

        mark.imageScaling = .scaleNone
        mark.imageAlignment = .alignCenter
        mark.contentTintColor = .labelColor
        mark.setAccessibilityElement(false)

        let lines = NSStackView(views: [titleLabel, timeTitle, resetLabel])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 3
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lines)

        for label in [usageLabel, timeLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        let textLeading = Self.ringSize + 10
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),

            mark.trailingAnchor.constraint(equalTo: trailingAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: Self.markSide),
            mark.heightAnchor.constraint(equalToConstant: Self.markSide),

            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),

            usageLabel.trailingAnchor.constraint(equalTo: mark.leadingAnchor, constant: -4),
            usageLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            usageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            timeLabel.trailingAnchor.constraint(equalTo: usageLabel.trailingAnchor),
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
        if hovered || lifted {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let fill = lifted
                ? NSColor.white.withAlphaComponent(dark ? 0.16 : 0.78)
                : NSColor.labelColor.withAlphaComponent(0.08)
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        RingGauge.draw(
            in: ringRect,
            usageRemaining: usageFraction,
            timeRemaining: timeFraction,
            color: fillColor,
            track: Theme.trackFill(appearance: effectiveAppearance),
            lineWidth: 5,
            showsValue: showsValue,
            showsUsed: showsUsed,
            tickWidth: 0.7,
            tickFromCenter: true
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyQuietColors()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        var dragged = false
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if next.type == .leftMouseUp {
                lifted = false
                needsDisplay = true
                if dragged {
                    onDragEnd?()
                } else if canToggle {
                    onToggle?()
                }
                NSCursor.pointingHand.set()
                break
            }
            let deltaX = next.locationInWindow.x - start.x
            let deltaY = next.locationInWindow.y - start.y
            if !dragged, hypot(deltaX, deltaY) < 4 { continue }
            if !dragged {
                dragged = true
                lifted = true
                NSCursor.closedHand.set()
            }
            onDrag?(deltaY)
            window.displayIfNeeded()
        }
    }

    func update(
        kind: PoolKind,
        pool: UsagePool?,
        inMenuBar: Bool,
        canToggle: Bool,
        showsUsed: Bool,
        at date: Date
    ) {
        self.canToggle = canToggle
        self.showsUsed = showsUsed
        let title = kind.title(showsUsed: showsUsed)
        kindTitle = title
        timeTitle.stringValue = kind.timeTitle(showsUsed: showsUsed)
        mark.image = inMenuBar ? Self.checkImage : nil
        mark.setAccessibilityLabel(inMenuBar ? "在菜单栏显示\(kind.shortTitle)" : "")

        guard let pool else {
            showUnavailable(kind: kind)
            return
        }
        let reading = pool.reading(at: date)
        let usagePercent = showsUsed ? reading.usageUsedPercent : reading.usageRemainingPercent
        let timePercent = showsUsed ? reading.timeElapsedPercent : reading.timeRemainingPercent
        let days = showsUsed ? pool.elapsedDays(at: date) : pool.remainingDays(at: date)
        let timeText = "\(kind.timeTitle(showsUsed: showsUsed)) \(days)天"
        showsValue = true
        usageFraction = reading.usageRemainingFraction
        timeFraction = reading.timeRemainingFraction
        fillColor = Theme.paceColor(reading.pace)
        usageLabel.stringValue = "\(usagePercent)%"
        usageLabel.textColor = fillColor
        titleLabel.stringValue = title
        titleLabel.textColor = .labelColor
        timeTitle.stringValue = timeText
        timeLabel.stringValue = "\(timePercent)%"
        resetLabel.stringValue = Theme.footerReset(from: pool.resetsAt)
        applyQuietColors()
        setAccessibilityLabel(title)
        setAccessibilityValue(
            "\(showsUsed ? "已用" : "剩余") \(usagePercent)%，\(timeText) \(timePercent)%，\(resetLabel.stringValue)"
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
        titleLabel.stringValue = kind.title(showsUsed: showsUsed)
        titleLabel.textColor = Theme.secondaryText(effectiveAppearance)
        usageLabel.stringValue = "—"
        usageLabel.textColor = Theme.secondaryText(effectiveAppearance)
        timeLabel.stringValue = "—"
        resetLabel.stringValue = "—"
        applyQuietColors()
        setAccessibilityLabel(kind.title(showsUsed: showsUsed))
        setAccessibilityValue("暂无数据")
        needsDisplay = true
    }

    private func applyQuietColors() {
        let color = Theme.tertiaryText(effectiveAppearance)
        timeTitle.textColor = color
        timeLabel.textColor = color
        resetLabel.textColor = color
    }

    private var pointerInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func syncHover() {
        guard window != nil else { return }
        setHovered(pointerInside)
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsDisplay = true
    }

    /// 对勾图画布小于 mark 盒子且居中，右缘离行尾是两侧留白的一半。
    static var markTrailingInset: CGFloat {
        guard let image = checkImage else { return 0 }
        return (markSide - image.size.width) / 2
    }

    private static let checkImage: NSImage? = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3.2, y: 8.3))
            path.line(to: NSPoint(x: 6.7, y: 4.7))
            path.line(to: NSPoint(x: 12.8, y: 11.5))
            path.lineWidth = 1.9
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

import AppKit

/// 面板里的一条额度。单击整行切换是否出现在菜单栏，按住拖动调整顺序。
@MainActor
final class ComparisonMeter: NSView {
    var onToggle: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "—")
    private let timeTitle = NSTextField(labelWithString: "周期剩余")
    private let timeLabel = NSTextField(labelWithString: "—")
    private let mark = NSImageView()

    private var usageFraction = 0.0
    private var timeFraction = 0.0
    private var fillColor = NSColor.systemGray
    private var showsValue = false
    private var ringRect = NSRect.zero
    private var hovered = false
    private var lifted = false
    private var canToggle = true
    private var kindTitle = ""

    private static let ringSize: CGFloat = 44
    private static let rowHeight: CGFloat = 60

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

        mark.imageScaling = .scaleNone
        mark.imageAlignment = .alignCenter
        mark.contentTintColor = .labelColor
        mark.setAccessibilityElement(false)

        for label in [titleLabel, usageLabel, timeTitle, timeLabel] {
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
            mark.widthAnchor.constraint(equalToConstant: 22),
            mark.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            usageLabel.trailingAnchor.constraint(equalTo: mark.leadingAnchor, constant: -4),
            usageLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            usageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            timeTitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeTitle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
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
        at date: Date
    ) {
        self.canToggle = canToggle
        kindTitle = kind.title
        timeTitle.stringValue = kind.timeTitle
        mark.image = inMenuBar ? Self.checkImage : nil
        mark.setAccessibilityLabel(inMenuBar ? "在菜单栏显示\(kind.shortTitle)" : "")

        guard let pool else {
            showUnavailable(kind: kind)
            return
        }
        let reading = pool.reading(at: date)
        showsValue = true
        usageFraction = reading.usageRemainingFraction
        timeFraction = reading.timeRemainingFraction
        fillColor = Theme.paceColor(reading.pace)
        usageLabel.stringValue = "\(reading.usageRemainingPercent)%"
        usageLabel.textColor = fillColor
        titleLabel.stringValue = kind.title
        titleLabel.textColor = .labelColor
        timeLabel.stringValue = "\(reading.timeRemainingPercent)%"
        applyQuietColors()
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
        titleLabel.stringValue = kind.title
        titleLabel.textColor = Theme.secondaryText(effectiveAppearance)
        usageLabel.stringValue = "—"
        usageLabel.textColor = Theme.secondaryText(effectiveAppearance)
        timeLabel.stringValue = "—"
        applyQuietColors()
        setAccessibilityLabel(kind.title)
        setAccessibilityValue("暂无数据")
        needsDisplay = true
    }

    private func applyQuietColors() {
        let color = Theme.tertiaryText(effectiveAppearance)
        timeTitle.textColor = color
        timeLabel.textColor = color
    }

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

    private static let checkImage: NSImage? = {
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        image?.isTemplate = true
        return image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
    }()
}

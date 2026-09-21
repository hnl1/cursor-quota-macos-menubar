import AppKit

@MainActor
final class ComparisonMeter: NSView {
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        usageLabel.alignment = .right
        timeTitle.font = .systemFont(ofSize: 11, weight: .medium)
        timeTitle.textColor = .secondaryLabelColor
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right

        for label in [titleLabel, usageLabel, timeTitle, timeLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.ringSize + 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            usageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            usageLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            usageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            timeTitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeTitle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
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

    func update(pool: UsagePool, at date: Date) {
        let reading = pool.reading(at: date)
        showsValue = true
        usageFraction = reading.usageRemainingFraction
        timeFraction = reading.timeRemainingFraction
        fillColor = Theme.paceColor(reading.pace)
        titleLabel.stringValue = pool.kind.title
        usageLabel.stringValue = "\(reading.usageRemainingPercent)%"
        usageLabel.textColor = fillColor
        timeTitle.stringValue = pool.kind.timeTitle
        timeLabel.stringValue = "\(reading.timeRemainingPercent)%"
        setAccessibilityLabel(pool.kind.title)
        setAccessibilityValue(
            "剩余 \(reading.usageRemainingPercent)%，\(pool.kind.timeTitle) \(reading.timeRemainingPercent)%"
        )
        needsLayout = true
        needsDisplay = true
    }

    func showUnavailable(title: String) {
        showsValue = false
        usageFraction = 0
        timeFraction = 0
        fillColor = .systemGray
        titleLabel.stringValue = title
        usageLabel.stringValue = "—"
        usageLabel.textColor = .secondaryLabelColor
        timeLabel.stringValue = "—"
        setAccessibilityLabel(title)
        setAccessibilityValue("暂无数据")
        needsDisplay = true
    }
}

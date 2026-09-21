import AppKit

@MainActor
final class HoverTipWindow: NSPanel {
    private let titleLabel = NSTextField(labelWithString: AppConfig.appName)
    private let statusLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private let footnoteLabel = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        animationBehavior = .utilityWindow
        contentView = makeContent()
    }

    func show(_ summary: HoverSummary, from button: NSView) {
        render(summary)
        fitToContent()
        setFrame(anchoredFrame(from: button), display: true)
        orderFrontRegardless()
    }

    func refresh(_ summary: HoverSummary) {
        guard isVisible else { return }
        render(summary)
        fitToContent()
        if let button = buttonAnchor() {
            setFrame(anchoredFrame(from: button), display: true)
        }
    }

    func dismiss() {
        orderOut(nil)
    }

    private var anchoredButton: NSView?

    private func buttonAnchor() -> NSView? { anchoredButton }

    private func makeContent() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        footnoteLabel.font = .systemFont(ofSize: 11)
        footnoteLabel.textColor = .tertiaryLabelColor
        footnoteLabel.lineBreakMode = .byWordWrapping
        footnoteLabel.maximumNumberOfLines = 4

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 3

        let header = NSStackView(views: [titleLabel, NSView(), statusLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 7
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(rowsStack)
        contentStack.addArrangedSubview(footnoteLabel)

        effect.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: effect.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            effect.widthAnchor.constraint(greaterThanOrEqualToConstant: 236),
            effect.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
        return effect
    }

    private func render(_ summary: HoverSummary) {
        titleLabel.stringValue = summary.title
        statusLabel.stringValue = summary.status
        statusLabel.textColor = summary.status == "过期" ? .systemOrange : .tertiaryLabelColor

        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in summary.rows {
            rowsStack.addArrangedSubview(makeRow(row))
        }
        rowsStack.isHidden = summary.rows.isEmpty

        footnoteLabel.stringValue = summary.footnote ?? ""
        footnoteLabel.isHidden = summary.footnote?.isEmpty != false
        footnoteLabel.preferredMaxLayoutWidth = 260
    }

    private func makeRow(_ row: HoverSummary.Row) -> NSView {
        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let detail = NSTextField(labelWithString: row.detail)
        detail.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        detail.alignment = .right
        if let pace = row.pace {
            detail.textColor = Theme.paceColor(pace)
        }

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        return stack
    }

    private func fitToContent() {
        contentView?.layoutSubtreeIfNeeded()
        let fitted = contentView?.fittingSize ?? NSSize(width: 260, height: 80)
        setContentSize(NSSize(width: max(236, fitted.width), height: fitted.height))
    }

    private func anchoredFrame(from button: NSView) -> NSRect {
        anchoredButton = button
        guard let window = button.window else {
            return frame
        }
        let buttonScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: buttonScreen.midX - frame.width / 2,
            y: buttonScreen.minY - frame.height - 6
        )
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            if origin.y < visible.minY {
                origin.y = buttonScreen.maxY + 6
            }
        }
        return NSRect(origin: origin, size: frame.size)
    }
}

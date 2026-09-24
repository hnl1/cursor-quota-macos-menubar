import AppKit

enum MenuBarScene: Equatable {
    case loading
    case unavailable
    /// nil 表示勾选了但没有数据，画灰色占位。
    case readings([UsageReading?], isStale: Bool)
}

enum GaugeImage {
    private enum Layout {
        static let ring: CGFloat = 22
        static let height: CGFloat = 22
        static let staleDot: CGFloat = 5
        static let lineWidth: CGFloat = 3
        static let tickOutset: CGFloat = 1.4
        /// 圆环和它自己的百分比之间
        static let textGap: CGFloat = 1
        /// 相邻两组之间。带百分比时留出文字后的空隙。
        static let entryGap: CGFloat = 6
        /// 不显示百分比时，圆环挨得更近。
        static let ringGap: CGFloat = 1
        static let dotGap: CGFloat = 3
    }

    private struct Entry {
        let text: String
        let usageRemaining: Double
        let timeRemaining: Double
        let color: NSColor
        let showsValue: Bool
    }

    private static var font: NSFont {
        .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    static func image(for scene: MenuBarScene, showsPercent: Bool = false, showsUsed: Bool = true) -> NSImage {
        let entries = entries(for: scene, showsPercent: showsPercent, showsUsed: showsUsed)
        let widths = entries.map { textWidth($0.text) }
        let stale = if case .readings(_, let isStale) = scene { isStale } else { false }

        let gap = widths.contains { $0 > 0 } ? Layout.entryGap : Layout.ringGap
        var width: CGFloat = 0
        for (index, textWidth) in widths.enumerated() {
            if index > 0 { width += gap }
            width += Layout.ring
            if textWidth > 0 { width += Layout.textGap + textWidth }
        }
        if stale { width += Layout.dotGap + Layout.staleDot }

        let size = NSSize(width: max(width, Layout.ring), height: Layout.height)
        let image = NSImage(size: size, flipped: false) { bounds in
            draw(entries: entries, widths: widths, gap: gap, stale: stale, showsUsed: showsUsed, in: bounds)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func entries(for scene: MenuBarScene, showsPercent: Bool, showsUsed: Bool) -> [Entry] {
        switch scene {
        case .loading:
            [placeholder("…")]
        case .unavailable:
            [placeholder("—")]
        case .readings(let readings, _):
            readings.isEmpty
                ? [placeholder("—")]
                : readings.map { reading in
                    guard let reading else { return placeholder(showsPercent ? "—" : "") }
                    return Entry(
                        text: showsPercent
                            ? "\(showsUsed ? reading.usageUsedPercent : reading.usageRemainingPercent)%"
                            : "",
                        usageRemaining: reading.usageRemainingFraction,
                        timeRemaining: reading.timeRemainingFraction,
                        color: Theme.paceColor(reading.pace),
                        showsValue: true
                    )
                }
        }
    }

    private static func placeholder(_ text: String) -> Entry {
        Entry(text: text, usageRemaining: 0, timeRemaining: 0, color: .systemGray, showsValue: false)
    }

    private static func draw(
        entries: [Entry],
        widths: [CGFloat],
        gap: CGFloat,
        stale: Bool,
        showsUsed: Bool,
        in bounds: NSRect
    ) {
        let track = NSColor.labelColor.withAlphaComponent(0.16)
        var x = bounds.minX
        for (index, entry) in entries.enumerated() {
            if index > 0 { x += gap }
            let ring = NSRect(
                x: x,
                y: bounds.midY - Layout.ring / 2,
                width: Layout.ring,
                height: Layout.ring
            )
            RingGauge.draw(
                in: ring,
                usageRemaining: entry.usageRemaining,
                timeRemaining: entry.timeRemaining,
                color: entry.color,
                track: track,
                lineWidth: Layout.lineWidth,
                showsValue: entry.showsValue,
                showsUsed: showsUsed,
                tickOutset: Layout.tickOutset,
                tickFromCenter: true
            )
            x += Layout.ring
            if widths[index] > 0 {
                x += Layout.textGap
                let text = attributed(entry.text)
                let textSize = text.size()
                text.draw(at: NSPoint(x: x, y: bounds.midY - textSize.height / 2))
                x += widths[index]
            }
        }

        guard stale else { return }
        let dot = NSRect(
            x: x + Layout.dotGap,
            y: bounds.midY - Layout.staleDot / 2,
            width: Layout.staleDot,
            height: Layout.staleDot
        )
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
    }

    private static func textWidth(_ text: String) -> CGFloat {
        attributed(text).size().width.rounded(.up)
    }
}

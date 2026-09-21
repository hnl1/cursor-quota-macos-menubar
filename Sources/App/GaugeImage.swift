import AppKit

enum MenuBarScene: Equatable {
    case loading
    case unavailable
    case reading(UsageReading, isStale: Bool)
}

enum GaugeImage {
    private enum Layout {
        static let ring: CGFloat = 22
        static let height: CGFloat = 22
        static let staleDot: CGFloat = 5
        static let lineWidth: CGFloat = 3
        static let tickOutset: CGFloat = 1.4
    }

    static func image(for scene: MenuBarScene) -> NSImage {
        let stale = if case .reading(_, let isStale) = scene { isStale } else { false }
        let width = Layout.ring + (stale ? Layout.staleDot + 3 : 0)
        let size = NSSize(width: width, height: Layout.height)
        let image = NSImage(size: size, flipped: false) { bounds in
            draw(scene: scene, in: bounds, stale: stale)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(scene: MenuBarScene, in bounds: NSRect, stale: Bool) {
        let ring = NSRect(x: bounds.minX, y: bounds.midY - Layout.ring / 2, width: Layout.ring, height: Layout.ring)
        let track = NSColor.labelColor.withAlphaComponent(0.16)
        switch scene {
        case .loading, .unavailable:
            RingGauge.draw(
                in: ring,
                usageRemaining: 0,
                timeRemaining: 0,
                color: .systemGray,
                track: track,
                lineWidth: Layout.lineWidth,
                showsValue: false,
                tickOutset: Layout.tickOutset
            )
        case .reading(let reading, _):
            RingGauge.draw(
                in: ring,
                usageRemaining: reading.usageRemainingFraction,
                timeRemaining: reading.timeRemainingFraction,
                color: Theme.paceColor(reading.pace),
                track: track,
                lineWidth: Layout.lineWidth,
                showsValue: true,
                tickOutset: Layout.tickOutset
            )
        }

        if stale {
            let dot = NSRect(
                x: bounds.maxX - Layout.staleDot,
                y: bounds.midY - Layout.staleDot / 2,
                width: Layout.staleDot,
                height: Layout.staleDot
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}

import AppKit

enum RingGauge {
    static func draw(
        in rect: NSRect,
        usageRemaining: Double,
        timeRemaining: Double,
        color: NSColor,
        track: NSColor,
        lineWidth: CGFloat,
        showsValue: Bool,
        showsUsed: Bool = false,
        tickOutset: CGFloat? = nil,
        tickWidth: CGFloat? = nil,
        tickFromCenter: Bool = false
    ) {
        guard rect.width > 1, rect.height > 1 else { return }
        let tickPad = tickOutset ?? max(1.8, lineWidth * 0.55)
        let inset = lineWidth / 2 + tickPad + 0.4
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        guard radius > 0 else { return }

        strokeCircle(center: center, radius: radius, width: lineWidth, color: track)
        guard showsValue else { return }

        let usage = min(max(usageRemaining, 0), 1)
        let time = min(max(timeRemaining, 0), 1)
        // 已用：用量弧和周期指针都从 12 点沿顺时针增长。剩余沿用原来的弧和指针。
        let arc = showsUsed ? 1 - usage : usage
        let pointer = showsUsed ? 1 - time : time
        strokeRemaining(
            center: center,
            radius: radius,
            fraction: visualUsageArc(arc, radius: radius),
            width: lineWidth,
            color: color
        )

        let radians = (90 - 360 * pointer) * .pi / 180
        let dx = Foundation.cos(radians)
        let dy = Foundation.sin(radians)
        let inner = tickFromCenter ? 0 : radius - lineWidth / 2 - tickPad
        let outer = tickFromCenter ? radius + lineWidth / 2 : radius + lineWidth / 2 + tickPad
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: center.x + inner * dx, y: center.y + inner * dy))
        tick.line(to: NSPoint(x: center.x + outer * dx, y: center.y + outer * dy))
        tick.lineWidth = tickWidth ?? max(1, lineWidth * 0.28)
        tick.lineCapStyle = tickFromCenter ? .butt : .round
        NSColor.labelColor.withAlphaComponent(0.78).setStroke()
        tick.stroke()
    }

    private static func strokeRemaining(
        center: NSPoint,
        radius: CGFloat,
        fraction: Double,
        width: CGFloat,
        color: NSColor
    ) {
        let value = min(max(fraction, 0), 1)
        if value >= 1 {
            strokeCircle(center: center, radius: radius, width: width, color: color)
            return
        }
        guard value > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * value,
            clockwise: true
        )
        arc.lineWidth = width
        arc.lineCapStyle = .butt
        color.setStroke()
        arc.stroke()
    }

    private static func visualUsageArc(
        _ fraction: Double,
        radius: CGFloat
    ) -> Double {
        let value = min(max(fraction, 0), 1)
        if value <= 0 || value >= 1 { return value }
        let circumference = 2 * Double.pi * Double(radius)
        let sliver = min(0.028, max(0.016, 2.2 / circumference))
        let gap = min(0.02, max(0.01, 1.6 / circumference))
        return min(max(value, sliver), 1 - gap)
    }

    private static func strokeCircle(
        center: NSPoint,
        radius: CGFloat,
        width: CGFloat,
        color: NSColor
    ) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

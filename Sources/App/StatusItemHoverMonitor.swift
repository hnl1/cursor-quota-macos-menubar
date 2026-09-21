import AppKit

/// Status-item buttons often swallow system tooltips. This monitor watches the
/// pointer against the item's screen frame and does not require Accessibility.
@MainActor
final class StatusItemHoverMonitor {
    var onChange: ((Bool) -> Void)?
    var buttonProvider: (() -> NSStatusBarButton?)?

    private var poll: Timer?
    private var pointerInside = false
    private let relay = HoverRelay()
    private var trackingArea: NSTrackingArea?

    func start() {
        stop()
        relay.onChange = { [weak self] inside in
            self?.setInside(inside)
        }
        attachTrackingArea()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if let button = buttonProvider?(), let trackingArea {
            button.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        setInside(false)
    }

    func tick() {
        setInside(Self.containsPointer(buttonProvider?()))
    }

    private func setInside(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        onChange?(inside)
    }

    private func attachTrackingArea() {
        guard let button = buttonProvider?() else { return }
        if let trackingArea {
            button.removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: relay,
            userInfo: nil
        )
        button.addTrackingArea(area)
        trackingArea = area
    }

    static func containsPointer(_ button: NSStatusBarButton?) -> Bool {
        guard let button, let window = button.window else { return false }
        let screenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return screenFrame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }
}

private final class HoverRelay: NSResponder {
    var onChange: ((Bool) -> Void)?

    override func mouseEntered(with event: NSEvent) {
        Task { @MainActor in
            self.onChange?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        Task { @MainActor in
            self.onChange?(false)
        }
    }
}

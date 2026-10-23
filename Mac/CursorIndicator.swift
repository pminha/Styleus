import AppKit
import QuartzCore

private final class CursorIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CursorFrameTarget: NSObject {
    weak var indicator: CursorIndicator?
    @objc func step(_ link: CADisplayLink) { indicator?.frame() }
}

/// A passive decoration: never activates Styleus, captures input, or changes the cursor.
final class CursorIndicator {
    var style = CursorIndicatorStyle.dragOnly {
        didSet { startIfVisible() }
    }
    private var state = CursorIndicatorState()
    private var position = CursorIndicatorPosition()
    private var panel: NSPanel?
    private var ring: CursorIndicatorView?
    private var displayLink: CADisplayLink?

    func receive(_ status: PencilStatus, buttonHeld: Bool, postedLocation: Point? = nil, at now: TimeInterval) {
        state.receive(status, buttonHeld: buttonHeld, at: now)
        if let postedLocation { position.record(postedLocation, at: now) }
        startIfVisible()
    }

    func clear() { state.clear(); hide() }

    private func startIfVisible() {
        guard state.presentation(at: ProcessInfo.processInfo.systemUptime, style: style) != nil else { hide(); return }
        guard displayLink == nil else { return }
        frame()
        guard let panel, panel.isVisible else { return }
        let target = CursorFrameTarget(); target.indicator = self
        // The window's display link follows the window across displays, including
        // ProMotion. There is no independent 60 Hz polling timer or animation tween.
        let link = panel.displayLink(target: target, selector: #selector(CursorFrameTarget.step(_:)))
        let maximum = Float(max(1, NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common); displayLink = link
    }

    fileprivate func frame() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let presentation = state.presentation(at: now, style: style) else { hide(); return }
        if panel == nil {
            let size = NSSize(width: 48, height: 48)
            let panel = CursorIndicatorPanel(contentRect: NSRect(origin: .zero, size: size),
                                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.animationBehavior = .none
            panel.isReleasedWhenClosed = false
            let view = CursorIndicatorView(frame: NSRect(origin: .zero, size: size))
            view.setAccessibilityElement(false)
            panel.contentView = view
            self.panel = panel; ring = view
        }
        ring?.presentation = presentation
        ring?.showsPressure = style == .pressure
        // Prefer this frame's latest posted input destination. After it is consumed,
        // sample the real cursor so local trackpad movements and OS adjustments follow.
        var mouse = NSEvent.mouseLocation
        if let point = position.takeLatest(at: now), let primary = NSScreen.screens.first?.frame,
           let converted = CoordinateMapping.appKitPoint(fromQuartz: point,
               primaryFrame: Rect(x: primary.minX, y: primary.minY, width: primary.width, height: primary.height)) {
            mouse = NSPoint(x: converted.x, y: converted.y)
        }
        let origin = NSPoint(x: mouse.x - 24, y: mouse.y - 24)
        if panel?.frame.origin != origin { panel?.setFrameOrigin(origin) }
        if panel?.isVisible == false { panel?.orderFrontRegardless() }
        ring?.displayIfNeeded()
    }

    private func hide() {
        displayLink?.invalidate(); displayLink = nil; position.clear()
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }
    deinit { displayLink?.invalidate() }
}

final class CursorIndicatorView: NSView {
    var showsPressure = true {
        didSet { if showsPressure != oldValue { needsDisplay = true } }
    }
    var presentation = CursorIndicatorPresentation(pressure: 0, activationPressure: 0.2, buttonHeld: false) {
        didSet { if presentation != oldValue { needsDisplay = true } }
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 18
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        let color: NSColor = presentation.buttonHeld ? .systemOrange : .systemBlue
        NSColor.black.withAlphaComponent(0.35).setStroke()
        circle.lineWidth = presentation.buttonHeld ? 4.5 : 3.5; circle.stroke()
        color.withAlphaComponent(presentation.buttonHeld ? 0.95 : 0.4).setStroke()
        circle.lineWidth = presentation.buttonHeld ? 2.5 : 1.5; circle.stroke()

        guard showsPressure else { return }
        // Clockwise pressure arc from twelve o'clock; a small white tick marks activation.
        if presentation.pressure > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - CGFloat(presentation.pressure) * 360, clockwise: true)
            arc.lineWidth = 3; arc.lineCapStyle = .round
            color.setStroke(); arc.stroke()
        }
        let angle = (90 - presentation.activationPressure * 360) * .pi / 180
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: center.x + cos(angle) * 15, y: center.y + sin(angle) * 15))
        tick.line(to: NSPoint(x: center.x + cos(angle) * 21, y: center.y + sin(angle) * 21))
        tick.lineWidth = 3; NSColor.black.withAlphaComponent(0.5).setStroke(); tick.stroke()
        tick.lineWidth = 1; NSColor.white.setStroke(); tick.stroke()
    }
}

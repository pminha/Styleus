#if os(macOS)
import CoreGraphics

/// Constructs the same events used by the Mac output without posting them.
/// Modifier state is supplied by the Mac at delivery time, never by the iPad.
struct MouseEventEncoder {
    static let keyboardModifiers: CGEventFlags = [
        .maskAlphaShift, .maskShift, .maskControl, .maskAlternate, .maskCommand,
        .maskHelp, .maskSecondaryFn, .maskNumericPad
    ]
    private var eventNumber: Int64 = 0
    private var heldEventNumber: [MouseButton: Int64] = [:]
    private var scrollEncoder = ScrollEventEncoder()

    mutating func event(_ effect: MouseEffect, source: CGEventSource? = nil,
                        modifiers: CGEventFlags) -> CGEvent? {
        let result: CGEvent?
        switch effect {
        case .move(let point, let dragging):
            result = mouse(type: dragging ? .leftMouseDragged : .mouseMoved, button: .left,
                           point: point, source: source)
            if dragging { result?.setIntegerValueField(.mouseEventNumber, value: heldEventNumber[.left] ?? 0) }
        case .down(let button, let point, let count):
            eventNumber += 1
            heldEventNumber[button] = eventNumber
            result = buttonEvent(button, down: true, point: point, count: count, source: source)
        case .up(let button, let point, let count):
            result = buttonEvent(button, down: false, point: point, count: count, source: source)
            heldEventNumber.removeValue(forKey: button)
        case .scroll(let sample):
            result = scrollEncoder.event(sample, source: source)
        case .zoom(let sample):
            // Native magnification carries its own semantics. Inheriting Ctrl
            // or Command here can change how a receiving app interprets it.
            return ZoomEventEncoder.event(sample, source: source)
        }
        // A private event source does not inherit the Mac keyboard's modifier
        // state. Replace keyboard bits on every event so key releases and changes
        // during a drag take effect, while retaining event-specific flags.
        if let result {
            result.flags = result.flags.subtracting(Self.keyboardModifiers)
                .union(modifiers.intersection(Self.keyboardModifiers))
        }
        return result
    }

    private func mouse(type: CGEventType, button: MouseButton, point: Point, source: CGEventSource?) -> CGEvent? {
        guard point.isFinite else { return nil }
        return CGEvent(mouseEventSource: source, mouseType: type,
                       mouseCursorPosition: CGPoint(x: point.x, y: point.y),
                       mouseButton: button == .left ? .left : .right)
    }

    private func buttonEvent(_ button: MouseButton, down: Bool, point: Point, count: Int,
                             source: CGEventSource?) -> CGEvent? {
        let type: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let event = mouse(type: type, button: button, point: point, source: source)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        event?.setIntegerValueField(.mouseEventNumber, value: heldEventNumber[button] ?? eventNumber)
        return event
    }
}
#endif

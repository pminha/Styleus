import Foundation

/// Call begin only for a new direct touch. A finger left over from a scroll or
/// pinch can therefore never start pointing or generate a click on lift.
struct FingerTrackpad<TouchID: Hashable> {
    private enum Phase { case firstTap, secondTap, moving, dragging }
    private struct Contact {
        let id: TouchID
        let origin: Point
        let beganAt: TimeInterval
        var previous: Point
        var lastSampleAt: TimeInterval
        var phase: Phase
        var holdAt: TimeInterval { beganAt + 0.25 }
    }

    var sensitivity = 1.5
    private var contact: Contact?
    private var lastTap: (point: Point, at: TimeInterval)?
    var activeTouch: TouchID? { contact?.id }
    var holdDeadline: TimeInterval? {
        guard let contact, contact.phase == .secondTap else { return nil }
        return contact.holdAt
    }

    mutating func begin(_ contacts: [TouchID: Point], at time: TimeInterval) -> [InputAction] {
        guard contacts.count == 1, let (id, point) = contacts.first, contact == nil,
              point.isFinite, time.isFinite else { return interrupt() }
        let second = TrackpadPointer.isSecondTap(at: point, time: time, after: lastTap)
        lastTap = nil
        contact = Contact(id: id, origin: point, beganAt: time, previous: point,
                          lastSampleAt: time, phase: second ? .secondTap : .firstTap)
        return []
    }

    mutating func hold(at time: TimeInterval) -> [InputAction] {
        guard let deadline = holdDeadline, time.isFinite, time >= deadline else { return [] }
        contact?.phase = .dragging
        return [.drag(true)]
    }

    mutating func move(to point: Point, at time: TimeInterval) -> [InputAction] {
        guard var current = contact else { return [] }
        guard point.isFinite, time.isFinite else { return interrupt() }
        guard time >= current.lastSampleAt else { return [] }
        let moved = hypot(point.x - current.origin.x, point.y - current.origin.y) > TrackpadPointer.tapSlop
        var actions: [InputAction] = []
        switch current.phase {
        case .firstTap where moved:
            current.phase = .moving
        case .secondTap where moved || time >= current.holdAt:
            current.phase = .dragging
            actions.append(.drag(true))
        default: break
        }
        if current.phase == .moving || current.phase == .dragging,
           let movement = TrackpadPointer.movement(from: current.previous, to: point, sensitivity: sensitivity) {
            actions.append(movement)
        }
        current.previous = point
        current.lastSampleAt = time
        contact = current
        return actions
    }

    mutating func end(at point: Point, time: TimeInterval) -> [InputAction] {
        guard let current = contact else { return [] }
        guard time.isFinite, time >= current.lastSampleAt else { return interrupt() }
        var actions = move(to: point, at: time)
        guard let finished = contact else { return actions }
        contact = nil
        switch finished.phase {
        case .firstTap where time - finished.beganAt < 0.35:
            lastTap = (point, time)
            actions.append(.click(.left, 1))
        case .secondTap: actions.append(.click(.left, 2))
        case .dragging: actions.append(.drag(false))
        default: break
        }
        return actions
    }

    mutating func interrupt() -> [InputAction] {
        let wasDragging = contact?.phase == .dragging
        contact = nil
        lastTap = nil
        return wasDragging ? [.drag(false)] : []
    }
}

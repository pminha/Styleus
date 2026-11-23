import Foundation

/// One gesture owns a sequence of direct touches. An interrupted sequence can
/// start another pointer gesture only after every finger has lifted.
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

    private struct TwoFingerTap {
        let origins: [TouchID: Point]
        let tapDeadline: TimeInterval?
        var lastSampleAt: TimeInterval
        var lifting = false

        func accepts(_ positions: [TouchID: Point]) -> Bool {
            positions.count == (lifting ? 1 : 2) && positions.allSatisfy { id, point in
                guard let origin = origins[id], point.isFinite else { return false }
                return hypot(point.x - origin.x, point.y - origin.y) <= TrackpadPointer.tapSlop
            }
        }
    }

    private struct ThreeFingerDrag {
        let ids: Set<TouchID>
        let origin: Point
        var previous: Point
        var lastSampleAt: TimeInterval
        var held = false

        static func center(of positions: [TouchID: Point]) -> Point {
            let sum = positions.values.reduce(Point.zero) { Point(x: $0.x + $1.x, y: $0.y + $1.y) }
            return Point(x: sum.x / 3, y: sum.y / 3)
        }
    }

    private enum Gesture {
        case idle
        case single(Contact)
        case pair(TwoFingerTap)
        case triple(ThreeFingerDrag)
    }

    var sensitivity = 1.5
    private var gesture = Gesture.idle
    private var lastTap: (point: Point, at: TimeInterval)?
    private static var maximumTapDuration: TimeInterval { 0.35 }
    private var contact: Contact? {
        if case .single(let contact) = gesture { return contact }
        return nil
    }
    var activeTouch: TouchID? { contact?.id }
    var holdDeadline: TimeInterval? {
        guard let contact, contact.phase == .secondTap else { return nil }
        return contact.holdAt
    }

    mutating func begin(_ contacts: [TouchID: Point], at time: TimeInterval, onEmptySurface: Bool) -> [InputAction] {
        guard time.isFinite, (1...3).contains(contacts.count),
              contacts.values.allSatisfy(\.isFinite) else { return interrupt() }
        var origins = contacts
        var tapDeadline: TimeInterval? = time + Self.maximumTapDuration
        switch gesture {
        case .idle:
            guard onEmptySurface else { return [] }
        case .single(let first):
            guard contacts.count > 1, contacts[first.id] != nil, time >= first.lastSampleAt,
                  first.phase != .dragging else { return interrupt() }
            // A finger already used to position the pointer may join a drag,
            // but its eventual lift must not complete a secondary click.
            if first.phase == .moving {
                tapDeadline = nil
            } else {
                origins[first.id] = first.origin
                tapDeadline = first.beganAt + Self.maximumTapDuration
            }
        case .pair(let pair):
            guard contacts.count == 3, !pair.lifting, time >= pair.lastSampleAt,
                  pair.origins.keys.allSatisfy({ contacts[$0] != nil }) else { return interrupt() }
        case .triple:
            return interrupt()
        }

        if contacts.count == 3 {
            let center = ThreeFingerDrag.center(of: contacts)
            guard center.isFinite else { return interrupt() }
            gesture = .triple(ThreeFingerDrag(ids: Set(contacts.keys), origin: center, previous: center, lastSampleAt: time))
        } else if contacts.count == 2 {
            gesture = .pair(TwoFingerTap(origins: origins, tapDeadline: tapDeadline, lastSampleAt: time))
        } else if let (id, point) = contacts.first {
            let second = TrackpadPointer.isSecondTap(at: point, time: time, after: lastTap)
            gesture = .single(Contact(id: id, origin: point, beganAt: time, previous: point,
                                      lastSampleAt: time, phase: second ? .secondTap : .firstTap))
        }
        lastTap = nil
        return []
    }

    mutating func hold(at time: TimeInterval) -> [InputAction] {
        guard var current = contact, current.phase == .secondTap, time.isFinite, time >= current.holdAt else { return [] }
        current.phase = .dragging
        gesture = .single(current)
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
        gesture = .single(current)
        return actions
    }

    mutating func moveGroup(_ positions: [TouchID: Point], at time: TimeInterval) -> [InputAction] {
        switch gesture {
        case .pair(var pair):
            guard time.isFinite else { return interrupt() }
            guard time >= pair.lastSampleAt else { return [] }
            guard pair.accepts(positions) else { return interrupt() }
            pair.lastSampleAt = time
            gesture = .pair(pair)
            return []
        case .triple(var drag):
            guard time.isFinite, positions.count == 3,
                  drag.ids.allSatisfy({ positions[$0]?.isFinite == true }) else { return interrupt() }
            guard time >= drag.lastSampleAt else { return [] }
            let center = ThreeFingerDrag.center(of: positions)
            guard center.isFinite, abs(center.x - drag.previous.x) <= 2000,
                  abs(center.y - drag.previous.y) <= 2000 else { return interrupt() }
            let from = drag.held ? drag.previous : drag.origin
            var actions: [InputAction] = []
            if !drag.held, hypot(center.x - drag.origin.x, center.y - drag.origin.y) > TrackpadPointer.tapSlop {
                drag.held = true
                actions.append(.drag(true))
            }
            if drag.held, let move = TrackpadPointer.movement(from: from, to: center, sensitivity: sensitivity) {
                actions.append(move)
            }
            drag.previous = center
            drag.lastSampleAt = time
            gesture = .triple(drag)
            return actions
        case .idle, .single: return []
        }
    }

    /// Positions include the lift sample for each ending touch. A staggered
    /// two-finger tap commits only on the last lift. A drag releases on the first.
    mutating func end(_ positions: [TouchID: Point], remaining: Int, at time: TimeInterval) -> [InputAction] {
        guard remaining < positions.count else { return [] }
        switch gesture {
        case .single(let current):
            guard remaining == 0, let point = positions[current.id] else { return interrupt() }
            return endSingle(at: point, time: time)
        case .pair(var pair):
            guard let deadline = pair.tapDeadline, time.isFinite, time >= pair.lastSampleAt, time < deadline,
                  pair.accepts(positions) else { return interrupt() }
            if remaining == 0 {
                gesture = .idle
                return [.click(.right, 1)]
            }
            pair.lifting = true
            pair.lastSampleAt = time
            gesture = .pair(pair)
            return []
        case .triple:
            let movement = moveGroup(positions, at: time)
            return movement + interrupt()
        case .idle: return []
        }
    }

    private mutating func endSingle(at point: Point, time: TimeInterval) -> [InputAction] {
        guard let current = contact else { return [] }
        guard time.isFinite, time >= current.lastSampleAt else { return interrupt() }
        var actions = move(to: point, at: time)
        guard let finished = contact else { return actions }
        gesture = .idle
        switch finished.phase {
        case .firstTap where time - finished.beganAt < Self.maximumTapDuration:
            lastTap = (point, time)
            actions.append(.click(.left, 1))
        case .secondTap: actions.append(.click(.left, 2))
        case .dragging: actions.append(.drag(false))
        default: break
        }
        return actions
    }

    mutating func interrupt() -> [InputAction] {
        defer { gesture = .idle; lastTap = nil }
        switch gesture {
        case .single(let contact) where contact.phase == .dragging: return [.drag(false)]
        case .triple(let drag) where drag.held: return [.drag(false)]
        default: return []
        }
    }
}

import Foundation

enum InputMode: String, Codable, CaseIterable { case trackpad, drawing }

enum InputAction: Codable, Equatable {
    case heartbeat
    case mode(InputMode)
    case relative(Point)
    case position(Point)
    case strokeBegin(Point)
    case strokeMove(Point)
    case strokeEnd
    case click(MouseButton, Int)
    case drag(Bool)
    case scroll(ScrollSample)
    case zoom(ZoomSample)
    case cancel
}

enum MouseButton: String, Codable { case left, right }

enum MouseEffect: Equatable {
    case move(Point, dragging: Bool)
    case down(MouseButton, Point, clickCount: Int)
    case up(MouseButton, Point, clickCount: Int)
    case scroll(ScrollSample)
    case zoom(ZoomSample)
}

/// Pure state machine. The receiver alone owns held mouse state.
struct InputState {
    private(set) var mode: InputMode = .trackpad
    private(set) var cursor = Point.zero
    private(set) var dragActive = false
    private(set) var strokeActive = false
    private(set) var zoomActive = false
    private enum Scrolling { case idle, contact, awaitingMomentum, momentum }
    private var scrolling = Scrolling.idle
    var target = Rect(x: 0, y: 0, width: 1, height: 1)
    var displays: [Rect] = []
    var leftHeld: Bool { dragActive || strokeActive }

    mutating func syncCursor(_ point: Point) {
        if !leftHeld && point.isFinite { cursor = point }
    }

    mutating func release() -> [MouseEffect] {
        let wasHeld = leftHeld
        dragActive = false
        strokeActive = false
        return (wasHeld ? [.up(.left, cursor, clickCount: 1)] : []) + cancelScroll() + cancelZoom()
    }

    private mutating func cancelZoom() -> [MouseEffect] {
        guard zoomActive else { return [] }
        zoomActive = false
        return [.zoom(ZoomSample(phase: .cancelled))]
    }

    private mutating func applyZoom(_ sample: ZoomSample) -> [MouseEffect] {
        guard !leftHeld, sample.isValid else { return cancelZoom() }
        switch sample.phase {
        case .began:
            let effects = cancelScroll() + cancelZoom()
            zoomActive = true
            return effects + [.zoom(sample)]
        case .changed:
            guard zoomActive else { return [] }
            return [.zoom(sample)]
        case .ended:
            guard zoomActive else { return [] }
            zoomActive = false
            return [.zoom(sample)]
        case .cancelled: return cancelZoom()
        }
    }

    private mutating func cancelScroll() -> [MouseEffect] {
        let previous = scrolling
        scrolling = .idle
        switch previous {
        case .contact: return [.scroll(ScrollSample(phase: .cancelled))]
        case .momentum: return [.scroll(ScrollSample(phase: .momentumEnded))]
        case .idle, .awaitingMomentum: return []
        }
    }

    private mutating func applyScroll(_ sample: ScrollSample) -> [MouseEffect] {
        guard !leftHeld, sample.delta.isFinite, abs(sample.delta.x) <= ScrollSample.maximumDelta, abs(sample.delta.y) <= ScrollSample.maximumDelta else {
            return cancelScroll()
        }
        var preceding: [MouseEffect] = []
        switch sample.phase {
        case .began: preceding = cancelScroll(); scrolling = .contact
        case .changed: guard scrolling == .contact else { return [] }
        case .ended:
            guard scrolling == .contact else { return [] }; scrolling = .awaitingMomentum
        case .cancelled: return cancelScroll()
        case .momentumBegan:
            guard scrolling == .awaitingMomentum else { return [] }; scrolling = .momentum
        case .momentumChanged: guard scrolling == .momentum else { return [] }
        case .momentumEnded:
            guard scrolling == .momentum else { return [] }; scrolling = .idle
        }
        return preceding + [.scroll(sample)]
    }

    mutating func apply(_ action: InputAction) -> [MouseEffect] {
        switch action {
        case .heartbeat: return []
        case .zoom(let sample): return applyZoom(sample)
        default:
            // Pointer and scrolling input must end magnification before starting
            // their own effects, including when the incoming action is rejected.
            let effects = cancelZoom()
            return effects + applyPointerOrScroll(action)
        }
    }

    private mutating func applyPointerOrScroll(_ action: InputAction) -> [MouseEffect] {
        switch action {
        case .heartbeat, .zoom: return [] // Handled before pointer/scroll dispatch.
        case .cancel: return release()
        case .mode(let newMode):
            let effects = release()
            mode = newMode
            return effects
        case .relative(let delta):
            guard mode == .trackpad, delta.isFinite, abs(delta.x) <= 10000, abs(delta.y) <= 10000 else { return [] }
            cursor = CoordinateMapping.constrainedToDisplays(Point(x: cursor.x + delta.x, y: cursor.y + delta.y), displays: displays)
            return cancelScroll() + [.move(cursor, dragging: leftHeld)]
        case .position(let normalized):
            guard mode == .drawing, let point = CoordinateMapping.absolute(normalized, target: target) else { return release() }
            let effects = release()
            cursor = point
            return effects + [.move(point, dragging: false)]
        case .strokeBegin(let normalized):
            guard mode == .drawing, let point = CoordinateMapping.absolute(normalized, target: target) else { return release() }
            // Always release BEFORE moving to a new origin. Never bridge two strokes.
            var effects = release()
            cursor = point
            effects += [.move(point, dragging: false), .down(.left, point, clickCount: 1)]
            strokeActive = true
            return effects
        case .strokeMove(let normalized):
            guard mode == .drawing, strokeActive else { return [] }
            guard let point = CoordinateMapping.absolute(normalized, target: target) else { return release() }
            cursor = point
            return [.move(point, dragging: true)]
        case .strokeEnd:
            return strokeActive ? release() : []
        case .click(let button, let count):
            guard mode == .trackpad, !leftHeld, (1...2).contains(count) else { return [] }
            // A tap emits one down/up pair. The second tap is labeled count 2; it
            // must not replay the first click and accidentally create a triple click.
            return cancelScroll() + [.down(button, cursor, clickCount: count), .up(button, cursor, clickCount: count)]
        case .drag(let enabled):
            guard mode == .trackpad, dragActive != enabled else { return [] }
            if !enabled { return release() }
            dragActive = true
            return cancelScroll() + [.down(.left, cursor, clickCount: 1)]
        case .scroll(let sample): return applyScroll(sample)
        }
    }
}

/// Pencil-only contact recognition. Force controls activation, not receiving-app ink width.
struct PencilInterpreter {
    var mode: InputMode = .trackpad
    var sensitivity: Double = 1.5
    var pressureThreshold: Double = 0.2
    var surface = Rect(x: 0, y: 0, width: 1, height: 1)
    var targetAspect: Double = 1
    private(set) var contact = false
    private(set) var blocked = false
    private(set) var pressure: Double = 0
    private var lastPoint: Point?
    private var startPoint = Point.zero
    private var beganAt: TimeInterval = 0
    private var lastSampleAt: TimeInterval = 0
    private var maxTravel: Double = 0
    private var drawing = false
    private var dragging = false
    private var didDrag = false
    private var lastTap: (point: Point, at: TimeInterval)?
    static let tapSlop = 6.0
    static let doubleTapInterval: TimeInterval = 0.35
    static let longPressDuration: TimeInterval = 0.5
    var activeArea: Rect? { CoordinateMapping.fittedArea(surface: surface, targetAspect: targetAspect) }
    var active: Bool { drawing || dragging }
    var activationPressure: Double { pressureThreshold.isFinite ? min(max(pressureThreshold, 0.05), 0.8) : 0.2 }
    var releasePressure: Double { activationPressure * 0.7 }
    var status: PencilStatus {
        PencilStatus(contact: contact && !blocked, pressure: contact && !blocked ? pressure : 0,
                     activationPressure: activationPressure)
    }

    mutating func begin(_ point: Point, pressure: Double = 0, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [InputAction] {
        guard point.isFinite, time.isFinite, !contact else { return [] }
        contact = true; blocked = false; lastPoint = point
        startPoint = point; beganAt = time; lastSampleAt = time; maxTravel = 0
        didDrag = false; dragging = false; drawing = false
        self.pressure = Self.validPressure(pressure)
        guard mode == .drawing else { return [] }
        guard let area = activeArea, let p = CoordinateMapping.normalized(point, in: area) else {
            blocked = true; return []
        }
        drawing = self.pressure >= activationPressure
        return [drawing ? .strokeBegin(p) : .position(p)]
    }

    mutating func move(_ point: Point, pressure: Double = 0, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [InputAction] {
        guard contact, !blocked else { return [] }
        guard point.isFinite, time.isFinite else { return interrupt() }
        guard time >= lastSampleAt else { return [] }
        lastSampleAt = time
        self.pressure = Self.validPressure(pressure)
        defer { lastPoint = point }
        if mode == .trackpad {
            guard let previous = lastPoint else { return [] }
            maxTravel = max(maxTravel, hypot(point.x - startPoint.x, point.y - startPoint.y))
            // Movement that still qualifies as a tap must not shift its click target.
            // Keep updating lastPoint so ignored wobble is never replayed on departure.
            guard maxTravel > Self.tapSlop else { return [] }
            lastTap = nil
            var actions: [InputAction] = []
            if dragging && self.pressure <= releasePressure {
                dragging = false; actions.append(.drag(false))
            } else if !dragging && self.pressure >= activationPressure && maxTravel > Self.tapSlop {
                dragging = true; didDrag = true; actions.append(.drag(true))
            }
            let gain = sensitivity.isFinite ? min(max(sensitivity, 0.2), 4) : 1.5
            let delta = Point(x: (point.x - previous.x) * gain, y: (point.y - previous.y) * gain)
            if delta != .zero { actions.append(.relative(delta)) }
            return actions
        }
        guard let area = activeArea, let p = CoordinateMapping.normalized(point, in: area) else {
            let actions: [InputAction] = drawing ? [.strokeEnd] : []
            drawing = false; blocked = true
            return actions
        }
        if drawing {
            if self.pressure <= releasePressure {
                drawing = false
                return [.strokeEnd, .position(p)]
            }
            return [.strokeMove(p)]
        }
        if self.pressure >= activationPressure {
            drawing = true
            return [.strokeBegin(p)]
        }
        return [.position(p)]
    }

    mutating func end(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [InputAction] {
        var effects: [InputAction] = drawing ? [.strokeEnd] : dragging ? [.drag(false)] : []
        if contact, !blocked, mode == .trackpad, !didDrag, maxTravel <= Self.tapSlop,
           time.isFinite, time >= lastSampleAt, let point = lastPoint {
            if time - beganAt >= Self.longPressDuration {
                effects.append(.click(.right, 1)); lastTap = nil
            } else {
                let doubleTap = lastTap.map {
                    time >= $0.at && time - $0.at <= Self.doubleTapInterval && hypot(point.x - $0.point.x, point.y - $0.point.y) <= 24
                } ?? false
                effects.append(.click(.left, doubleTap ? 2 : 1))
                lastTap = doubleTap ? nil : (point, time)
            }
        } else { lastTap = nil }
        contact = false; blocked = false; drawing = false; lastPoint = nil
        dragging = false; didDrag = false; pressure = 0
        return effects
    }

    mutating func interrupt() -> [InputAction] {
        blocked = contact; drawing = false; lastPoint = nil
        dragging = false; didDrag = false; lastTap = nil; pressure = 0
        return [.cancel]
    }

    private static func validPressure(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
}

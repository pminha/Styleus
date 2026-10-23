import Foundation

enum ZoomPhase: String, Codable, CaseIterable {
    case began, changed, ended, cancelled
}

struct ZoomSample: Codable, Equatable {
    static let maximumMagnification = 0.5
    var magnification: Double = 0
    var phase: ZoomPhase

    var isValid: Bool {
        magnification.isFinite && abs(magnification) <= Self.maximumMagnification &&
            (phase == .changed || magnification == 0)
    }
}

struct TwoFingerGestureUpdate: Equatable {
    var scrollDeltas: [Point] = []
    var zoomSamples: [ZoomSample] = []
}

/// Resolves a pair of direct touches to scrolling or pinching, then keeps that
/// decision until the pair changes. The disabled path delegates to the existing
/// scroll recognizer, preserving its response and finger-replacement behavior.
struct TwoFingerGestureInterpreter<TouchID: Hashable> {
    var pinchZoomEnabled = false
    var reverseVertical: Bool {
        get { scroll.reverseVertical }
        set { scroll.reverseVertical = newValue }
    }
    var reverseHorizontal: Bool {
        get { scroll.reverseHorizontal }
        set { scroll.reverseHorizontal = newValue }
    }
    var sensitivity: Double {
        get { scroll.sensitivity }
        set { scroll.sensitivity = newValue }
    }
    var acceleratesWithSpeed: Bool {
        get { scroll.acceleratesWithSpeed }
        set { scroll.acceleratesWithSpeed = newValue }
    }
    var active: Bool { scroll.active }
    var zoomActive: Bool { selection == .zoom }

    private enum Selection { case pending, scroll, zoom }
    private var selection = Selection.pending
    private var scroll = TwoFingerScrollInterpreter<TouchID>()
    private var contacts: [TouchID: Point] = [:]
    private var previousContacts: [TouchID: Point] = [:]
    private var pair: Set<TouchID> = []
    private var origin = Point.zero
    private var originSpan: Double = 0
    private var previousSpan: Double = 0
    private var previousTime: TimeInterval?
    private var blockedUntilLift = false
    private static var minimumInitialSpan: Double { 32 }
    private static var minimumSpan: Double { 16 }
    private static var pinchDistance: Double { 6 }
    private static var pinchFraction: Double { 0.03 }

    mutating func update(_ contacts: [TouchID: Point], at now: TimeInterval,
                         pencilDown: Bool = false) -> TwoFingerGestureUpdate {
        self.contacts = contacts
        guard pinchZoomEnabled else {
            return TwoFingerGestureUpdate(scrollDeltas: scroll.update(contacts, at: now, pencilDown: pencilDown))
        }
        if pencilDown {
            let result = interrupt()
            blockedUntilLift = true
            return TwoFingerGestureUpdate(zoomSamples: result)
        }
        if contacts.isEmpty {
            let end = zoomActive ? [ZoomSample(phase: .ended)] : []
            _ = scroll.update(contacts, at: now)
            resetPair()
            blockedUntilLift = false
            return TwoFingerGestureUpdate(zoomSamples: end)
        }
        guard !blockedUntilLift else { return TwoFingerGestureUpdate() }
        guard now.isFinite, contacts.count <= 2, contacts.values.allSatisfy(\.isFinite) else {
            return TwoFingerGestureUpdate(zoomSamples: interrupt())
        }
        if let previousTime, now < previousTime { return TwoFingerGestureUpdate() }
        previousTime = now
        guard contacts.count == 2 else {
            if zoomActive {
                let end = [ZoomSample(phase: .ended)]
                _ = interrupt()
                return TwoFingerGestureUpdate(zoomSamples: end)
            }
            _ = scroll.update(contacts, at: now)
            resetPair()
            return TwoFingerGestureUpdate()
        }
        let identifiers = Set(contacts.keys)
        let points = Array(contacts.values)
        let center = Point(x: (points[0].x + points[1].x) / 2,
                           y: (points[0].y + points[1].y) / 2)
        let span = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        guard center.isFinite, span.isFinite else {
            return TwoFingerGestureUpdate(zoomSamples: interrupt())
        }
        guard identifiers == pair else {
            // A pinching contact may not become scrolling when one finger is
            // replaced. Require the remaining hand to lift completely first.
            if zoomActive { return TwoFingerGestureUpdate(zoomSamples: interrupt()) }
            resetPair()
            pair = identifiers
            origin = center
            originSpan = span
            previousSpan = span
            previousContacts = contacts
            previousTime = now
            // Seed the original scroll origin without delivering movement while
            // the winner is still undecided.
            _ = scroll.update(contacts, at: now)
            return TwoFingerGestureUpdate()
        }
        guard contacts.allSatisfy({ id, point in
            guard let previous = previousContacts[id] else { return false }
            return abs(point.x - previous.x) <= 2000 && abs(point.y - previous.y) <= 2000
        }) else { return TwoFingerGestureUpdate(zoomSamples: interrupt()) }
        previousContacts = contacts

        if selection == .scroll {
            return TwoFingerGestureUpdate(scrollDeltas: scroll.update(contacts, at: now))
        }
        if zoomActive {
            guard span >= Self.minimumSpan else {
                return TwoFingerGestureUpdate(zoomSamples: interrupt())
            }
            let factor = span / previousSpan
            guard factor.isFinite, (0.5...2).contains(factor) else {
                return TwoFingerGestureUpdate(zoomSamples: interrupt())
            }
            previousSpan = span
            return TwoFingerGestureUpdate(zoomSamples: Self.changes(for: factor))
        }

        let travel = hypot(center.x - origin.x, center.y - origin.y)
        let spanTravel = abs(span - originSpan)
        let canScroll = travel >= TwoFingerScrollInterpreter<TouchID>.activationDistance
        let canZoom = originSpan >= Self.minimumInitialSpan && span >= Self.minimumSpan &&
            spanTravel >= Self.pinchDistance && abs(span / originSpan - 1) >= Self.pinchFraction
        let zoomWins = canZoom && (!canScroll ||
            spanTravel / Self.pinchDistance > travel / TwoFingerScrollInterpreter<TouchID>.activationDistance)
        if zoomWins {
            let factor = span / originSpan
            guard factor.isFinite, (0.5...2).contains(factor) else {
                return TwoFingerGestureUpdate(zoomSamples: interrupt())
            }
            scroll.interrupt()
            selection = .zoom
            previousSpan = span
            return TwoFingerGestureUpdate(zoomSamples: [ZoomSample(phase: .began)] + Self.changes(for: factor))
        }
        if canScroll {
            selection = .scroll
            return TwoFingerGestureUpdate(scrollDeltas: scroll.update(contacts, at: now))
        }
        return TwoFingerGestureUpdate()
    }

    /// Mode, geometry, settings, cancellation, Pencil contact, and disconnection
    /// discard gesture history. Resting contacts must all lift before restarting.
    mutating func interrupt() -> [ZoomSample] {
        let result = zoomActive ? [ZoomSample(phase: .cancelled)] : []
        scroll.interrupt()
        blockedUntilLift = !contacts.isEmpty
        resetPair()
        return result
    }

    private mutating func resetPair() {
        selection = .pending
        pair.removeAll()
        previousContacts.removeAll()
        origin = .zero
        originSpan = 0
        previousSpan = 0
        previousTime = nil
    }

    private static func changes(for factor: Double) -> [ZoomSample] {
        guard factor != 1 else { return [] }
        // Multiplication preserves the complete measured distance if an unusually
        // fast expansion needs two individually bounded wire samples.
        if factor > 1 + ZoomSample.maximumMagnification {
            let first = 1 + ZoomSample.maximumMagnification
            return [ZoomSample(magnification: first - 1, phase: .changed),
                    ZoomSample(magnification: factor / first - 1, phase: .changed)]
        }
        return [ZoomSample(magnification: factor - 1, phase: .changed)]
    }
}

import Foundation

/// Scroll gain follows finger speed, measured before the user's sensitivity or
/// axis reversal. Filtering changes gain only; it never delays finger travel.
struct ScrollResponse {
    private var previousTime: TimeInterval?
    private var velocity = Point.zero
    private var pending = Point.zero
    private var previousGain = 1.0

    mutating func begin(at now: TimeInterval) {
        self = ScrollResponse()
        if now.isFinite { previousTime = now }
    }

    mutating func gain(for delta: Point, at now: TimeInterval) -> Double {
        guard delta.isFinite, now.isFinite else { begin(at: now); return 1 }
        guard let previousTime, now >= previousTime else { begin(at: now); return 1 }
        pending.x += delta.x; pending.y += delta.y
        let elapsed = now - previousTime
        // Multiple callbacks can share a timestamp. Deliver their distance with
        // the current gain and include it in the next valid velocity estimate.
        guard elapsed > 0 else { return previousGain }
        self.previousTime = now
        guard elapsed <= 0.10 else { begin(at: now); return 1 }
        let target = Point(x: pending.x / elapsed, y: pending.y / elapsed)
        pending = .zero
        guard target.isFinite else { begin(at: now); return 1 }
        let timeConstant = 0.025
        let decay = exp(-elapsed / timeConstant)
        // Integrate the filtered velocity over this interval, rather than using
        // its endpoint, so 60/120 Hz callbacks have comparable response.
        let weight = timeConstant * (1 - decay) / elapsed
        let average = Point(x: target.x + (velocity.x - target.x) * weight,
                            y: target.y + (velocity.y - target.y) * weight)
        velocity = Point(x: target.x + (velocity.x - target.x) * decay,
                         y: target.y + (velocity.y - target.y) * decay)
        let speed = hypot(average.x, average.y)
        let normalized = max(0, speed - 80) / 1000
        // 1× for fine movements, approaching 6× for fast swipes. The gain is
        // bounded, not the output speed: faster input continues to travel farther.
        previousGain = 1 + 5 * (1 - 1 / (1 + normalized * normalized))
        return previousGain
    }
}

/// Direct touches only. Pencil contact and interruptions suppress a resting hand
/// until all its contacts lift; direct touches never move or click the pointer.
struct TwoFingerScrollInterpreter<TouchID: Hashable> {
    var reverseVertical = false
    var reverseHorizontal = false
    var sensitivity = 1.0
    var acceleratesWithSpeed = true
    private(set) var active = false
    private var contacts: [TouchID: Point] = [:]
    private var pair: Set<TouchID> = []
    private var origin = Point.zero
    private var previous: Point?
    private var blockedUntilLift = false
    private var response = ScrollResponse()
    static var activationDistance: Double { 4 }

    mutating func update(_ contacts: [TouchID: Point], at now: TimeInterval, pencilDown: Bool = false) -> [Point] {
        self.contacts = contacts
        if pencilDown {
            interrupt()
            blockedUntilLift = true
            return []
        }
        if contacts.isEmpty {
            blockedUntilLift = false
            resetGesture()
            return []
        }
        guard !blockedUntilLift else { return [] }
        guard now.isFinite, contacts.count <= 2, contacts.values.allSatisfy(\.isFinite) else {
            interrupt()
            return []
        }
        guard contacts.count == 2 else {
            resetGesture()
            return []
        }
        let identifiers = Set(contacts.keys)
        let center = contacts.values.reduce(Point.zero) { result, point in
            Point(x: result.x + point.x / 2, y: result.y + point.y / 2)
        }
        guard pair == identifiers, let previous else {
            resetGesture()
            pair = identifiers
            origin = center
            self.previous = center
            response.begin(at: now)
            return []
        }
        self.previous = center
        let step = Point(x: center.x - previous.x, y: center.y - previous.y)
        guard step.isFinite, abs(step.x) <= 2000, abs(step.y) <= 2000 else {
            interrupt()
            return []
        }
        let gain = acceleratesWithSpeed ? response.gain(for: step, at: now) : 1
        let delta: Point
        if active {
            delta = step
        } else {
            delta = Point(x: center.x - origin.x, y: center.y - origin.y)
            guard hypot(delta.x, delta.y) >= Self.activationDistance else { return [] }
            active = true
        }
        guard delta.isFinite, abs(delta.x) <= 2000, abs(delta.y) <= 2000 else {
            interrupt()
            return []
        }
        // Keep fractional motion through recognition, velocity estimation, and
        // transport. Only the Mac's integer point field needs final quantization.
        let scale = (sensitivity.isFinite ? min(max(sensitivity, 0.25), 4) : 1) * gain
        let scaled = Point(x: delta.x * scale * (reverseHorizontal ? -1 : 1),
                           y: delta.y * scale * (reverseVertical ? -1 : 1))
        guard abs(scaled.x) <= ScrollSample.maximumDelta, abs(scaled.y) <= ScrollSample.maximumDelta else { interrupt(); return [] }
        return scaled == .zero ? [] : [scaled]
    }

    mutating func interrupt() {
        blockedUntilLift = !contacts.isEmpty
        resetGesture()
    }

    private mutating func resetGesture() {
        active = false
        pair.removeAll()
        previous = nil
        response = ScrollResponse()
    }
}

enum ScrollPhase: String, Codable {
    case began, changed, ended, cancelled
    case momentumBegan, momentumChanged, momentumEnded
}

struct ScrollSample: Codable, Equatable {
    // Allows fast, accelerated swipes at 4× sensitivity and 60 Hz without
    // confusing valid scaled distance with an implausible raw touch jump.
    static let maximumDelta = 16_384.0
    var delta: Point = .zero
    var phase: ScrollPhase
}

/// Frame-paced scrolling and bounded, cancellable momentum. Times are local
/// monotonic timestamps; nothing is retained across an interruption/reconnect.
struct ScrollMotion {
    private enum State { case idle, contact, awaitingLift, momentum }
    private var state = State.idle
    private var pending = Point.zero
    private var position = Point.zero
    private var samples: [(time: TimeInterval, position: Point)] = []
    private var began = false
    private var velocity = Point.zero
    private var releasedAt: TimeInterval = 0
    private var previousFrame: TimeInterval = 0
    private var momentumStartedAt: TimeInterval = 0
    var needsFrames: Bool { state == .contact || state == .momentum }

    mutating func move(_ delta: Point, at now: TimeInterval) {
        guard delta.isFinite, abs(delta.x) <= ScrollSample.maximumDelta, abs(delta.y) <= ScrollSample.maximumDelta, now.isFinite else { return }
        if state != .contact {
            state = .contact; pending = .zero; position = .zero; began = false
            samples = [(now - 1.0 / 60, .zero)]
        }
        guard now >= (samples.last?.time ?? now) else { return }
        pending = Point(x: pending.x + delta.x, y: pending.y + delta.y)
        position = Point(x: position.x + delta.x, y: position.y + delta.y)
        if samples.last?.time == now { samples[samples.count - 1] = (now, position) }
        else { samples.append((now, position)) }
        while samples.count > 2 && samples[1].time < now - 0.08 { samples.removeFirst() }
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
    }

    mutating func end(at now: TimeInterval, allFingersUp: Bool) -> [ScrollSample] {
        guard state == .contact, now.isFinite else { return [] }
        if pending != .zero, let last = samples.last,
           now < last.time || now - last.time > 0.10 { return cancel() }
        var result = flush()
        if began { result.append(ScrollSample(phase: .ended)) }
        velocity = .zero
        if let first = samples.first, let last = samples.last, now >= last.time,
           now - last.time <= 0.10, last.time > first.time {
            let duration = last.time - first.time
            velocity = Point(x: (last.position.x - first.position.x) / duration,
                             y: (last.position.y - first.position.y) / duration)
        }
        releasedAt = now; state = .awaitingLift
        if allFingersUp { result += liftRemainingFingers(at: now) }
        return result
    }

    mutating func liftRemainingFingers(at now: TimeInterval) -> [ScrollSample] {
        guard state == .awaitingLift else { return [] }
        guard now.isFinite, now >= releasedAt, now - releasedAt <= 0.08,
              hypot(velocity.x, velocity.y) >= 60 else {
            state = .idle; return []
        }
        state = .momentum; previousFrame = now; momentumStartedAt = now
        return [ScrollSample(phase: .momentumBegan)]
    }

    mutating func tick(at now: TimeInterval) -> [ScrollSample] {
        if state == .contact {
            if pending != .zero, let last = samples.last,
               !now.isFinite || now < last.time || now - last.time > 0.10 { return cancel() }
            return flush()
        }
        guard state == .momentum else { return [] }
        let elapsed = now - previousFrame
        guard now.isFinite, elapsed >= 0, elapsed <= 0.10,
              now - momentumStartedAt < 2, hypot(velocity.x, velocity.y) >= 8 else {
            return cancel()
        }
        guard elapsed > 0 else { return [] }
        previousFrame = now
        let decay = exp(-4.2 * elapsed)
        let delta = Point(x: velocity.x * (1 - decay) / 4.2, y: velocity.y * (1 - decay) / 4.2)
        // Public Quartz precise-scroll point fields are integer-valued. Do not
        // stretch the tail into isolated one-point steps separated by zero frames.
        // Fast flicks keep their measured speed; only invalid/implausible frames
        // are rejected by the same per-frame bound used for contact input.
        guard delta.isFinite, abs(delta.x) <= ScrollSample.maximumDelta, abs(delta.y) <= ScrollSample.maximumDelta,
              max(abs(delta.x), abs(delta.y)) >= 1 else { return cancel() }
        velocity = Point(x: velocity.x * decay, y: velocity.y * decay)
        return [ScrollSample(delta: delta, phase: .momentumChanged)]
    }

    mutating func cancel() -> [ScrollSample] {
        let result: [ScrollSample]
        if state == .momentum { result = [ScrollSample(phase: .momentumEnded)] }
        else if state == .contact && began { result = [ScrollSample(phase: .cancelled)] }
        else { result = [] }
        self = ScrollMotion()
        return result
    }

    private mutating func flush() -> [ScrollSample] {
        guard pending != .zero else { return [] }
        guard pending.isFinite, abs(pending.x) <= ScrollSample.maximumDelta, abs(pending.y) <= ScrollSample.maximumDelta else { return cancel() }
        let result = ScrollSample(delta: pending, phase: began ? .changed : .began)
        pending = .zero; began = true
        return [result]
    }
}

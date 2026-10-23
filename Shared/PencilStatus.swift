import Foundation

/// Display-only telemetry. Mouse actions, not these values, control held input.
struct PencilStatus: Codable, Equatable {
    var contact: Bool
    var pressure: Double
    var activationPressure: Double
    static let inactive = PencilStatus(contact: false, pressure: 0, activationPressure: 0.2)

    var isValid: Bool {
        pressure.isFinite && (0...1).contains(pressure) &&
        activationPressure.isFinite && (0.05...0.8).contains(activationPressure) &&
        (contact || pressure == 0)
    }
}

/// Input packets carry the latest sample. Extra updates cover stationary pressure
/// changes at most 30 times a second, with no sample queue and no delayed input.
struct PencilStatusRelay {
    private(set) var latest = PencilStatus.inactive
    private var sent: PencilStatus?
    private var sentAt: TimeInterval?
    static let interval: TimeInterval = 1.0 / 30

    mutating func update(_ sample: PencilStatus) { latest = sample.isValid ? sample : .inactive }
    mutating func markSent(at now: TimeInterval) { sent = latest; sentAt = now }
    func needsUpdate(at now: TimeInterval) -> Bool {
        guard now.isFinite, latest != sent else { return false }
        return sentAt.map { now - $0 >= Self.interval } ?? true
    }
}

struct CursorIndicatorPresentation: Equatable {
    var pressure: Double
    var activationPressure: Double
    var buttonHeld: Bool
}

enum CursorIndicatorStyle: String, CaseIterable {
    case off, dragOnly, pressure

    init(saved: String?) {
        self = saved.flatMap(Self.init(rawValue:)) ?? .off
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .dragOnly: return "Dragging only"
        case .pressure: return "Pressure and dragging"
        }
    }
}

/// One latest posted destination for the next display frame, never a motion queue.
/// This keeps the decoration from sampling the cursor before a posted event arrives.
struct CursorIndicatorPosition {
    static let maximumAge: TimeInterval = 0.1
    private var pending: (point: Point, at: TimeInterval)?

    mutating func record(_ point: Point, at now: TimeInterval) {
        guard point.isFinite, now.isFinite else { return }
        guard pending.map({ now >= $0.at }) ?? true else { return }
        pending = (point, now)
    }

    mutating func takeLatest(at now: TimeInterval) -> Point? {
        defer { pending = nil }
        guard let pending, now.isFinite, now >= pending.at,
              now - pending.at <= Self.maximumAge else { return nil }
        return pending.point
    }

    mutating func clear() { pending = nil }
}

struct CursorIndicatorState {
    static let freshness: TimeInterval = 0.45
    private var sample = PencilStatus.inactive
    private var receivedAt: TimeInterval?
    private var buttonHeld = false

    /// Call only after session, lease, sequence, geometry and permission checks.
    mutating func receive(_ status: PencilStatus, buttonHeld: Bool, at now: TimeInterval) {
        sample = status.isValid ? status : .inactive
        receivedAt = now.isFinite ? now : nil
        self.buttonHeld = buttonHeld
    }

    mutating func clear() { self = Self() }

    func presentation(at now: TimeInterval, style: CursorIndicatorStyle) -> CursorIndicatorPresentation? {
        guard style != .off else { return nil }
        let age = receivedAt.map { now - $0 }
        let fresh = age.map { $0.isFinite && $0 >= 0 && $0 <= Self.freshness } ?? false
        guard buttonHeld || (style == .pressure && fresh && sample.contact) else { return nil }
        return CursorIndicatorPresentation(pressure: style == .pressure && fresh ? sample.pressure : 0,
                                           activationPressure: sample.activationPressure, buttonHeld: buttonHeld)
    }
}

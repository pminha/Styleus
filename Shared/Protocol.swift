import Foundation

enum WireProtocol {
    static let version = 6
}

struct TargetDescription: Codable, Equatable {
    var name: String
    var rect: Rect
}

struct ServerState: Codable {
    var version = WireProtocol.version
    var session: UUID
    var lease: UUID
    var geometry: UInt64
    var target: TargetDescription
    var dragActive: Bool
    var acknowledgedSequence: UInt64 = 0
    var inputAllowed: Bool = true
}

extension ServerState {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        session = try values.decode(UUID.self, forKey: .session)
        lease = try values.decode(UUID.self, forKey: .lease)
        geometry = try values.decode(UInt64.self, forKey: .geometry)
        target = try values.decode(TargetDescription.self, forKey: .target)
        if version == WireProtocol.version {
            dragActive = try values.decode(Bool.self, forKey: .dragActive)
            acknowledgedSequence = try values.decode(UInt64.self, forKey: .acknowledgedSequence)
            inputAllowed = try values.decode(Bool.self, forKey: .inputAllowed)
        } else {
            // Decode older configuration envelopes only to report an actionable version error.
            // They must never enable input or become an active session.
            acknowledgedSequence = 0
            inputAllowed = false
            dragActive = false
        }
    }
}

struct InputPacket: Codable {
    var session: UUID
    var lease: UUID
    var geometry: UInt64
    var sequence: UInt64
    var action: InputAction
    var pencilStatus: PencilStatus = .inactive
}

enum WireMessage: Codable {
    case state(ServerState)
    case input(InputPacket)
    case ping(TimingProbe)
    case pong(TimingProbe)
}

struct TimingProbe: Codable, Equatable {
    var session: UUID
    var nonce: UUID
}

/// App-to-app round-trip time on a single monotonic clock, not Pencil-to-screen latency.
/// One outstanding probe and at most 20 samples; nothing survives a new session.
struct RoundTripMeasurement {
    let session: UUID
    private var pending: (probe: TimingProbe, sentAt: TimeInterval)?
    private(set) var milliseconds: [Double] = []
    static let timeout: TimeInterval = 2

    init(session: UUID) { self.session = session }

    var median: Double? {
        guard !milliseconds.isEmpty else { return nil }
        let sorted = milliseconds.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    mutating func begin(now: TimeInterval) -> TimingProbe? {
        guard now.isFinite else { return nil }
        if let pending, now - pending.sentAt <= Self.timeout { return nil }
        let probe = TimingProbe(session: session, nonce: UUID())
        pending = (probe, now)
        return probe
    }

    @discardableResult
    mutating func accept(_ probe: TimingProbe, now: TimeInterval) -> Double? {
        guard let pending, probe == pending.probe else { return nil }
        self.pending = nil
        let elapsed = now - pending.sentAt
        guard elapsed.isFinite, elapsed >= 0, elapsed <= Self.timeout else { return nil }
        let sample = elapsed * 1000
        milliseconds.append(sample)
        if milliseconds.count > 20 { milliseconds.removeFirst() }
        return sample
    }
}

/// A server-issued short-lived lease rejects stale TCP input without assuming synchronized clocks.
struct SessionGate {
    let session: UUID
    private(set) var geometry: UInt64
    private(set) var lastSequence: UInt64 = 0
    private(set) var lastAccepted: TimeInterval
    private var leases: [UUID: TimeInterval] = [:]
    static let leaseLifetime: TimeInterval = 0.75
    static let silenceLimit: TimeInterval = 1.0

    init(session: UUID = UUID(), geometry: UInt64, now: TimeInterval) {
        self.session = session; self.geometry = geometry; self.lastAccepted = now
    }

    mutating func issueLease(now: TimeInterval) -> UUID {
        leases = leases.filter { now - $0.value <= Self.leaseLifetime }
        let token = UUID(); leases[token] = now
        return token
    }

    mutating func changeGeometry(_ revision: UInt64) {
        geometry = revision; leases.removeAll()
    }

    mutating func accept(_ packet: InputPacket, now: TimeInterval) -> Bool {
        guard packet.session == session, packet.geometry == geometry,
              packet.sequence > lastSequence, let issued = leases[packet.lease],
              now >= issued, now - issued <= Self.leaseLifetime else { return false }
        lastSequence = packet.sequence; lastAccepted = now
        return true
    }

    func expired(now: TimeInterval) -> Bool { now - lastAccepted > Self.silenceLimit }

    // A timing probe must not renew input authority, issue a lease, or keep held input alive.
    func reply(to probe: TimingProbe, now: TimeInterval) -> TimingProbe? {
        guard probe.session == session, !expired(now: now) else { return nil }
        return probe
    }
}

struct FrameDecoder {
    static let limit = 32768
    private var data = Data()

    mutating func append(_ incoming: Data) throws -> [Data] {
        data.append(incoming)
        var frames: [Data] = []
        while data.count >= 4 {
            let count = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0 && count <= Self.limit else { throw ProtocolError.invalidFrame }
            guard data.count >= count + 4 else { break }
            frames.append(Data(data.dropFirst(4).prefix(count)))
            data.removeFirst(count + 4)
        }
        guard data.count <= Self.limit + 4 else { throw ProtocolError.invalidFrame }
        return frames
    }

    static func encode(_ message: WireMessage) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard !body.isEmpty && body.count <= limit else { throw ProtocolError.invalidFrame }
        var size = UInt32(body.count).bigEndian
        var framed = withUnsafeBytes(of: &size) { Data($0) }
        framed.append(body)
        return framed
    }
}

enum ProtocolError: LocalizedError {
    case invalidFrame, invalidPairing, keychain(OSStatus), randomFailure
    var errorDescription: String? {
        switch self {
        case .invalidFrame: return "Invalid connection data. Reconnect to your paired Mac."
        case .invalidPairing: return "This pairing code is not valid. Scan the code displayed by Styleus on your Mac."
        case .keychain(let status): return "Secure storage could not be accessed (\(status))."
        case .randomFailure: return "A secure pairing key could not be created."
        }
    }
}

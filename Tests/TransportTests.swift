import XCTest
import Network
import Security
@testable import StyleusCore

final class TransportTests: XCTestCase {
    // The shipping client factory requires the selected interface. Tests replace it with loopback;
    // no localhost or cleartext fallback exists in either application.
    private func parameters(_ pair: PairingCredential) -> NWParameters {
        let params = LocalTransport.parameters(pair, mode: .wifi)
        params.requiredInterfaceType = .loopback
        return params
    }

    func testAuthenticatedEncryptedRoundTripDeliversInputAndDisconnectReleases() throws {
        let pair = try PairingCredential.create()
        let listener = try NWListener(using: parameters(pair), on: .any)
        let complete = expectation(description: "Encrypted input received and release delivered")
        var server: MessageChannel?
        var client: MessageChannel?
        var engine = InputState()
        engine.target = Rect(x: -1000, y: 100, width: 1000, height: 600)
        var gate = SessionGate(geometry: 1, now: ProcessInfo.processInfo.systemUptime)
        var received: [MouseEffect] = []
        var closedAfterDrag = false
        var configuration: ServerState?
        var timing: RoundTripMeasurement?

        listener.newConnectionHandler = { connection in
            let channel = MessageChannel(connection); server = channel
            channel.onReady = {
                let meta = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
                XCTAssertNotNil(meta)
                if let meta {
                    XCTAssertEqual(sec_protocol_metadata_get_negotiated_tls_protocol_version(meta.securityProtocolMetadata), .TLSv12)
                    XCTAssertEqual(sec_protocol_metadata_get_negotiated_tls_ciphersuite(meta.securityProtocolMetadata).rawValue, 0x00A8)
                }
                XCTAssertNil(LocalTransport.mode(for: connection.currentPath), "Loopback must not be labeled as a shipping connection")
                let lease = gate.issueLease(now: ProcessInfo.processInfo.systemUptime)
                channel.send(.state(ServerState(session: gate.session, lease: lease, geometry: 1,
                    target: TargetDescription(name: "Test", rect: engine.target), dragActive: false)))
            }
            channel.onMessage = { message in
                if case .ping(let probe) = message {
                    let acceptedAt = gate.lastAccepted
                    let reply = gate.reply(to: probe, now: ProcessInfo.processInfo.systemUptime)
                    XCTAssertEqual(reply, probe)
                    XCTAssertEqual(gate.lastAccepted, acceptedAt)
                    XCTAssertEqual(gate.lastSequence, 0)
                    if let reply { channel.send(.pong(reply)) }
                    return
                }
                guard case .input(let packet) = message else { XCTFail("Expected input"); return }
                guard gate.accept(packet, now: ProcessInfo.processInfo.systemUptime) else { XCTFail("Fresh input rejected"); return }
                received += engine.apply(packet.action)
                if packet.sequence == 4 {
                    XCTAssertTrue(engine.dragActive)
                    closedAfterDrag = true
                    client?.close("Test disconnect while dragging")
                }
            }
            channel.onClose = { _ in
                received += engine.release()
                if closedAfterDrag {
                    XCTAssertFalse(engine.leftHeld)
                    XCTAssertEqual(received.last, .up(.left, Point(x: 12, y: 8), clickCount: 1))
                    complete.fulfill()
                }
            }
            channel.start()
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                let channel = MessageChannel(NWConnection(host: "127.0.0.1", port: port, using: self.parameters(pair)))
                client = channel
                channel.onMessage = { message in
                    if case .state(let state) = message {
                        configuration = state
                        timing = RoundTripMeasurement(session: state.session)
                        if let probe = timing?.begin(now: ProcessInfo.processInfo.systemUptime) { channel.send(.ping(probe)) }
                        return
                    }
                    guard case .pong(let probe) = message, let state = configuration else { XCTFail("Expected timing reply"); return }
                    XCTAssertNotNil(timing?.accept(probe, now: ProcessInfo.processInfo.systemUptime))
                    let actions: [InputAction] = [.mode(.trackpad), .drag(true), .relative(Point(x: 12, y: 8)), .heartbeat]
                    for (i, action) in actions.enumerated() {
                        channel.send(.input(InputPacket(session: state.session, lease: state.lease, geometry: 1, sequence: UInt64(i + 1), action: action)))
                    }
                }
                channel.start()
            }
            if case .failed(let error) = state { XCTFail(error.localizedDescription); complete.fulfill() }
        }
        listener.start(queue: .main)
        wait(for: [complete], timeout: 8)
        server?.onClose = nil; server?.close(); client?.close(); listener.cancel()
    }

    func testWrongPairingSecretCannotAuthenticate() throws {
        let pair = try PairingCredential.create()
        var impostor = try PairingCredential.create(); impostor.id = pair.id
        let listener = try NWListener(using: parameters(pair), on: .any)
        let denied = expectation(description: "Wrong key is rejected")
        var server: MessageChannel?
        var client: MessageChannel?
        listener.newConnectionHandler = { connection in
            let channel = MessageChannel(connection); server = channel
            channel.onReady = { XCTFail("Wrong-key peer authenticated") }
            channel.start()
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                let channel = MessageChannel(NWConnection(host: "127.0.0.1", port: port, using: self.parameters(impostor)))
                client = channel
                channel.onReady = { XCTFail("Wrong key established a client session") }
                channel.onClose = { _ in denied.fulfill() }
                channel.start()
            }
            if case .failed(let error) = state { XCTFail(error.localizedDescription); denied.fulfill() }
        }
        listener.start(queue: .main)
        wait(for: [denied], timeout: 8)
        client?.onClose = nil; client?.close(); server?.close(); listener.cancel()
    }
}

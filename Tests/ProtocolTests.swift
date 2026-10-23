import XCTest
@testable import StyleusCore

final class ProtocolTests: XCTestCase {
    private func configuration(version: Int) -> Data {
        let dragField = version < 4 ? "dragLocked" : "dragActive"
        return Data("""
        {"state":{"_0":{"version":\(version),"session":"6C16A347-1F34-4514-9222-09C44C03116C",
        "lease":"D6DC8D8A-52EC-4A4A-8FE6-4A7E4F89982D","geometry":1,
        "target":{"name":"Test","rect":{"x":0,"y":0,"width":1920,"height":1080}},"\(dragField)":false}}}
        """.utf8)
    }

    func testLegacyMacConfigurationCanReportVersionMismatchWithoutGrantingInput() throws {
        for version in [1, 2, 3, 4, 5, 6] {
            guard case .state(let state) = try JSONDecoder().decode(WireMessage.self, from: configuration(version: version)) else {
                return XCTFail("Expected a configuration envelope")
            }
            XCTAssertNotEqual(state.version, WireProtocol.version)
            XCTAssertFalse(state.inputAllowed)
            XCTAssertFalse(state.zoomAvailable)
            XCTAssertEqual(state.acknowledgedSequence, 0)
        }
    }

    func testCurrentConfigurationRequiresAndPreservesSafetyFields() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(WireMessage.self, from: configuration(version: WireProtocol.version)))
        let state = ServerState(session: UUID(), lease: UUID(), geometry: 3,
            target: TargetDescription(name: "Test", rect: Rect(x: 0, y: 0, width: 1920, height: 1080)),
            dragActive: false, acknowledgedSequence: 17, inputAllowed: false, zoomAvailable: true)
        let encoded = try JSONEncoder().encode(WireMessage.state(state))
        guard case .state(let decoded) = try JSONDecoder().decode(WireMessage.self, from: encoded) else {
            return XCTFail("Expected a configuration envelope")
        }
        XCTAssertEqual(decoded.version, WireProtocol.version)
        XCTAssertEqual(decoded.acknowledgedSequence, 17)
        XCTAssertFalse(decoded.inputAllowed)
        XCTAssertTrue(decoded.zoomAvailable)
    }

    func testSessionRejectsReplayExpiredLeaseAndOldGeometry() {
        var gate = SessionGate(geometry: 1, now: 0)
        let token = gate.issueLease(now: 0)
        var packet = InputPacket(session: gate.session, lease: token, geometry: 1, sequence: 1, action: .drag(true))
        XCTAssertTrue(gate.accept(packet, now: 0.1))
        XCTAssertFalse(gate.accept(packet, now: 0.2))
        packet.sequence = 2
        XCTAssertFalse(gate.accept(packet, now: 0.8))
        packet.lease = gate.issueLease(now: 0.8)
        XCTAssertTrue(gate.accept(packet, now: 0.9))
        gate.changeGeometry(2)
        packet.sequence = 3
        XCTAssertFalse(gate.accept(packet, now: 1))
        packet.geometry = 2
        XCTAssertFalse(gate.accept(packet, now: 1))
        packet.lease = gate.issueLease(now: 1)
        XCTAssertTrue(gate.accept(packet, now: 1))
        let newConnection = SessionGate(geometry: 2, now: 1)
        packet.session = newConnection.session
        XCTAssertFalse(gate.accept(packet, now: 1.1))
        XCTAssertTrue(gate.expired(now: 2.01))
    }

    func testFragmentedAndCombinedFramesAndOversizeRejection() throws {
        let state = ServerState(session: UUID(), lease: UUID(), geometry: 1,
                                target: TargetDescription(name: "Test", rect: Rect(x: 0, y: 0, width: 100, height: 200)), dragActive: false)
        let encoded = try FrameDecoder.encode(.state(state))
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(encoded.prefix(2)).count, 0)
        XCTAssertEqual(try decoder.append(encoded.dropFirst(2) + encoded).count, 2)
        XCTAssertThrowsError(try decoder.append(Data([0x7f, 0xff, 0xff, 0xff])))
    }

    func testHighEntropyPairingRoundtripAndMalformedInputs() throws {
        let pair = try PairingCredential.create()
        XCTAssertEqual(pair.secret.count, 32)
        XCTAssertEqual(try PairingCredential.parse(pair.code), pair)
        XCTAssertNotEqual(pair, try PairingCredential.create())
        XCTAssertThrowsError(try PairingCredential.parse("123456"))
        XCTAssertThrowsError(try PairingCredential.parse("styleus:1:\(UUID()):YWJj"))
    }
}

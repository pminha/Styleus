import XCTest
import Network
@testable import StyleusCore

final class SafetyTests: XCTestCase {
    func testExplicitTransportSelectionCannotFallBackToAnotherInterfaceType() throws {
        let pair = try PairingCredential.create()
        for mode in ConnectionMode.allCases {
            let parameters = LocalTransport.parameters(pair, mode: mode)
            XCTAssertEqual(parameters.requiredInterfaceType, mode == .usb ? .wiredEthernet : .wifi)
            XCTAssertTrue(parameters.acceptLocalOnly)
            XCTAssertFalse(parameters.includePeerToPeer)
            let browser = LocalTransport.browserParameters(mode: mode)
            XCTAssertEqual(browser.requiredInterfaceType, parameters.requiredInterfaceType)
            XCTAssertFalse(browser.includePeerToPeer)
        }
    }

    func testListenerExcludesNonLocalTransportTypes() throws {
        let parameters = LocalTransport.listenerParameters(try PairingCredential.create())
        XCTAssertTrue(parameters.acceptLocalOnly)
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertEqual(Set(parameters.prohibitedInterfaceTypes ?? []), Set([.cellular, .other, .loopback]))
        XCTAssertNil(LocalTransport.mode(for: nil))
    }

    func testWatchdogReleaseAndReconnectNeverRestoreHeldState() {
        var engine = InputState()
        var gate = SessionGate(geometry: 1, now: 0)
        let lease = gate.issueLease(now: 0)
        let packet = InputPacket(session: gate.session, lease: lease, geometry: 1, sequence: 1, action: .drag(true))
        XCTAssertTrue(gate.accept(packet, now: 0.1))
        _ = engine.apply(packet.action)
        XCTAssertTrue(engine.leftHeld)
        XCTAssertTrue(gate.expired(now: 1.11))
        XCTAssertEqual(engine.release(), [.up(.left, .zero, clickCount: 1)])
        var newGate = SessionGate(geometry: 1, now: 1.2)
        XCTAssertFalse(newGate.accept(packet, now: 1.21))
        XCTAssertFalse(engine.leftHeld)
    }

    func testInterruptedContactCannotResumeUntilLift() {
        for mode in InputMode.allCases {
            var pen = PencilInterpreter()
            pen.mode = mode
            pen.surface = Rect(x: 0, y: 0, width: 500, height: 500)
            _ = pen.begin(Point(x: 100, y: 100))
            _ = pen.interrupt()
            XCTAssertEqual(pen.move(Point(x: 400, y: 400)), [])
            XCTAssertEqual(pen.begin(Point(x: 200, y: 200)), [])
            _ = pen.end()
            _ = pen.begin(Point(x: 300, y: 300))
            XCTAssertFalse(pen.blocked)
        }
    }

    func testInvalidStrokeCoordinateReleasesRatherThanLeavingButtonHeld() {
        var engine = InputState()
        _ = engine.apply(.mode(.drawing))
        _ = engine.apply(.strokeBegin(Point(x: 0.5, y: 0.5)))
        XCTAssertTrue(engine.leftHeld)
        let effects = engine.apply(.strokeMove(Point(x: 2, y: 0.5)))
        XCTAssertEqual(effects.count, 1)
        XCTAssertFalse(engine.leftHeld)
    }
}

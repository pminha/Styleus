import XCTest
@testable import StyleusCore

final class PencilStatusTests: XCTestCase {
    private let contact = PencilStatus(contact: true, pressure: 0.6, activationPressure: 0.2)

    func testIndicatorFramesUseNewestPostedDestinationWithoutReplayingEarlierMotion() {
        var position = CursorIndicatorPosition()
        position.record(Point(x: 1, y: 2), at: 1)
        position.record(Point(x: 50, y: 30), at: 1.004)
        position.record(Point(x: 80, y: 45), at: 1.008)
        XCTAssertEqual(position.takeLatest(at: 1.01), Point(x: 80, y: 45))
        XCTAssertNil(position.takeLatest(at: 1.02)) // Fall back to actual cursor; no queued path.
        position.record(Point(x: 20, y: 60), at: 2)
        position.record(Point(x: 10, y: 10), at: 1.9)
        XCTAssertEqual(position.takeLatest(at: 2.01), Point(x: 20, y: 60))
    }

    func testIndicatorDestinationsExpireAndClearWithoutAffectingInput() {
        var position = CursorIndicatorPosition()
        position.record(Point(x: 20, y: 30), at: 1)
        XCTAssertNil(position.takeLatest(at: 1.101))
        position.record(Point(x: 20, y: 30), at: 2)
        position.clear()
        XCTAssertNil(position.takeLatest(at: 2.01))
        position.record(Point(x: .nan, y: 0), at: 3)
        position.record(.zero, at: .nan)
        XCTAssertNil(position.takeLatest(at: 3.01))
        position.record(.zero, at: 4)
        XCTAssertNil(position.takeLatest(at: 3.99))
        XCTAssertNil(position.takeLatest(at: 4.01))
    }

    func testDragOnlyHidesOrdinaryContactAndPressureAnimation() {
        var indicator = CursorIndicatorState()
        indicator.receive(contact, buttonHeld: false, at: 1)
        XCTAssertNil(indicator.presentation(at: 1, style: .dragOnly))
        XCTAssertNotNil(indicator.presentation(at: 1, style: .pressure))
        indicator.receive(contact, buttonHeld: true, at: 1.1)
        XCTAssertEqual(indicator.presentation(at: 1.1, style: .dragOnly),
                       CursorIndicatorPresentation(pressure: 0, activationPressure: 0.2, buttonHeld: true))
        XCTAssertNil(indicator.presentation(at: 1.1, style: .off))
        indicator.receive(contact, buttonHeld: false, at: 1.2)
        XCTAssertNil(indicator.presentation(at: 1.2, style: .dragOnly))
        XCTAssertNotNil(indicator.presentation(at: 1.2, style: .pressure))
        indicator.clear()
        for style in CursorIndicatorStyle.allCases {
            XCTAssertNil(indicator.presentation(at: 1.3, style: style))
        }
    }

    func testOptionalRingDefaultsOffAndRemembersExplicitChoices() {
        XCTAssertEqual(CursorIndicatorStyle(saved: nil), .off)
        XCTAssertEqual(CursorIndicatorStyle(saved: "unknown"), .off)
        XCTAssertEqual(CursorIndicatorStyle(saved: "dragOnly"), .dragOnly)
        XCTAssertEqual(CursorIndicatorStyle(saved: "pressure"), .pressure)
        XCTAssertEqual(CursorIndicatorStyle(saved: "off"), .off)
    }

    func testInterpreterReportsContactWithoutConfusingPressureWithDrag() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, pressure: 0.6, at: 1)
        XCTAssertEqual(pencil.status, contact)
        XCTAssertFalse(pencil.active)
        _ = pencil.interrupt()
        XCTAssertEqual(pencil.status, .inactive)
        _ = pencil.move(Point(x: 10, y: 0), pressure: 1, at: 1.1)
        XCTAssertEqual(pencil.status, .inactive)
        _ = pencil.end(at: 1.2)
        _ = pencil.begin(.zero, pressure: 0.6, at: 2)
        _ = pencil.end(at: 2.1)
        XCTAssertEqual(pencil.status, .inactive)
    }

    func testDrawingMarginStopsStatusUntilFreshContact() {
        var pencil = PencilInterpreter()
        pencil.mode = .drawing
        pencil.surface = Rect(x: 0, y: 0, width: 100, height: 100)
        pencil.targetAspect = 2
        _ = pencil.begin(Point(x: 50, y: 50), pressure: 0.6, at: 1)
        XCTAssertTrue(pencil.status.contact)
        _ = pencil.move(Point(x: 50, y: 0), pressure: 0.6, at: 1.1)
        XCTAssertFalse(pencil.status.contact)
        _ = pencil.move(Point(x: 50, y: 50), pressure: 0.6, at: 1.2)
        XCTAssertFalse(pencil.status.contact)
    }

    func testRelayCoalescesToLatestAndPiggybackAvoidsExtraPackets() {
        var relay = PencilStatusRelay()
        relay.markSent(at: 1)
        relay.update(contact)
        XCTAssertFalse(relay.needsUpdate(at: 1.01))
        var newest = contact; newest.pressure = 0.7
        relay.update(newest)
        XCTAssertTrue(relay.needsUpdate(at: 1.04))
        XCTAssertEqual(relay.latest, newest)
        relay.markSent(at: 1.04)
        XCTAssertFalse(relay.needsUpdate(at: 2))
        relay.update(.inactive)
        XCTAssertTrue(relay.needsUpdate(at: 2))
        relay.markSent(at: 2) // The lift/click packet already carries the update.
        XCTAssertFalse(relay.needsUpdate(at: 2.04))
        XCTAssertFalse(relay.needsUpdate(at: .nan))
    }

    func testIndicatorUsesActualHeldStateAndHidesAfterLiftExpiryOrClear() {
        var indicator = CursorIndicatorState()
        XCTAssertNil(indicator.presentation(at: 1, style: .pressure))
        indicator.receive(contact, buttonHeld: false, at: 1)
        XCTAssertEqual(indicator.presentation(at: 1.1, style: .pressure), CursorIndicatorPresentation(pressure: 0.6, activationPressure: 0.2, buttonHeld: false))
        XCTAssertNil(indicator.presentation(at: 1.46, style: .pressure))
        indicator.receive(contact, buttonHeld: true, at: 2)
        XCTAssertEqual(indicator.presentation(at: 2.1, style: .pressure)?.buttonHeld, true)
        // Expired telemetry cannot erase a button the input engine still holds.
        XCTAssertEqual(indicator.presentation(at: 2.5, style: .pressure), CursorIndicatorPresentation(pressure: 0, activationPressure: 0.2, buttonHeld: true))
        indicator.receive(contact, buttonHeld: false, at: 3)
        XCTAssertEqual(indicator.presentation(at: 3.1, style: .pressure)?.buttonHeld, false)
        indicator.receive(.inactive, buttonHeld: false, at: 3.2)
        XCTAssertNil(indicator.presentation(at: 3.2, style: .pressure))
        indicator.receive(contact, buttonHeld: true, at: 4)
        indicator.clear()
        XCTAssertNil(indicator.presentation(at: 4, style: .pressure))
    }

    func testInvalidSamplesCannotProducePressureOrPhantomContact() {
        for bad in [PencilStatus(contact: true, pressure: .nan, activationPressure: 0.2),
                    PencilStatus(contact: true, pressure: 1.1, activationPressure: 0.2),
                    PencilStatus(contact: true, pressure: 0.3, activationPressure: .infinity),
                    PencilStatus(contact: true, pressure: 0.3, activationPressure: 0.01),
                    PencilStatus(contact: false, pressure: 0.3, activationPressure: 0.2)] {
            XCTAssertFalse(bad.isValid)
            var indicator = CursorIndicatorState()
            indicator.receive(bad, buttonHeld: false, at: 1)
            XCTAssertNil(indicator.presentation(at: 1, style: .pressure))
            var relay = PencilStatusRelay()
            relay.update(bad)
            XCTAssertEqual(relay.latest, .inactive)
        }
    }

    func testStatusRoundTripIsProtectedBySessionGateAndCannotClick() throws {
        var gate = SessionGate(geometry: 2, now: 1)
        let packet = InputPacket(session: gate.session, lease: gate.issueLease(now: 1), geometry: 2,
                                 sequence: 1, action: .heartbeat, pencilStatus: contact)
        var decoder = FrameDecoder()
        let frame = try XCTUnwrap(decoder.append(FrameDecoder.encode(.input(packet))).first)
        guard case .input(let received) = try JSONDecoder().decode(WireMessage.self, from: frame) else {
            return XCTFail("Expected input packet")
        }
        XCTAssertEqual(received.pencilStatus, contact)
        XCTAssertTrue(gate.accept(received, now: 1.1))
        XCTAssertFalse(gate.accept(received, now: 1.2))
        var mouse = InputState()
        XCTAssertEqual(mouse.apply(received.action), [])
        XCTAssertFalse(mouse.leftHeld)
        var newSession = SessionGate(geometry: 2, now: 1.2)
        XCTAssertFalse(newSession.accept(received, now: 1.2))
    }
}

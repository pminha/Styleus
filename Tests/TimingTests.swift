import XCTest
@testable import StyleusCore

final class TimingTests: XCTestCase {
    func testProbeMustMatchSessionAndNonceAndCannotBeReplayed() throws {
        let session = UUID()
        var timing = RoundTripMeasurement(session: session)
        let probe = try XCTUnwrap(timing.begin(now: 10))
        XCTAssertNil(timing.begin(now: 10.1), "Only one probe may be outstanding")
        XCTAssertNil(timing.accept(TimingProbe(session: UUID(), nonce: probe.nonce), now: 10.1))
        XCTAssertNil(timing.accept(TimingProbe(session: session, nonce: UUID()), now: 10.1))
        XCTAssertEqual(try XCTUnwrap(timing.accept(probe, now: 10.02)), 20, accuracy: 0.0001)
        XCTAssertNil(timing.accept(probe, now: 10.03))
        XCTAssertEqual(timing.milliseconds.count, 1)
        let reconnected = RoundTripMeasurement(session: UUID())
        XCTAssertNil(reconnected.median)
        XCTAssertTrue(reconnected.milliseconds.isEmpty)
    }

    func testInvalidOrExpiredTimingCannotPolluteMeasurements() throws {
        var timing = RoundTripMeasurement(session: UUID())
        XCTAssertNil(timing.begin(now: .infinity))
        let old = try XCTUnwrap(timing.begin(now: 1))
        let replacement = try XCTUnwrap(timing.begin(now: 3.01))
        XCTAssertNil(timing.accept(old, now: 3.02))
        XCTAssertNil(timing.accept(replacement, now: 3))
        let invalid = try XCTUnwrap(timing.begin(now: 4))
        XCTAssertNil(timing.accept(invalid, now: .nan))
        let expired = try XCTUnwrap(timing.begin(now: 5))
        XCTAssertNil(timing.accept(expired, now: 7.01))
        XCTAssertNil(timing.median)
    }

    func testMedianIncludesOnlyTwentyRecentSamples() throws {
        var timing = RoundTripMeasurement(session: UUID())
        for index in 0..<25 {
            let now = Double(index) * 3
            let probe = try XCTUnwrap(timing.begin(now: now))
            XCTAssertNotNil(timing.accept(probe, now: now + Double(index) / 1000))
        }
        XCTAssertEqual(timing.milliseconds.count, 20)
        XCTAssertEqual(try XCTUnwrap(timing.median), 14.5, accuracy: 0.0001)
    }

    func testTimingRepliesNeverRenewInputAuthority() {
        let gate = SessionGate(geometry: 1, now: 10)
        let probe = TimingProbe(session: gate.session, nonce: UUID())
        XCTAssertEqual(gate.reply(to: probe, now: 10.5), probe)
        XCTAssertEqual(gate.lastAccepted, 10)
        XCTAssertEqual(gate.lastSequence, 0)
        XCTAssertNil(gate.reply(to: TimingProbe(session: UUID(), nonce: probe.nonce), now: 10.5))
        XCTAssertTrue(gate.expired(now: 11.01))
        XCTAssertNil(gate.reply(to: probe, now: 11.01))
    }
}

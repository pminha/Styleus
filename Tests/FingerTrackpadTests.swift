import XCTest
@testable import StyleusCore

final class FingerTrackpadTests: XCTestCase {
    private let origin = Point(x: 50, y: 40)

    private func tap(_ finger: inout FingerTrackpad<Int>, at time: TimeInterval, point: Point) -> [InputAction] {
        XCTAssertEqual(finger.begin([1: point], at: time), [])
        return finger.end(at: point, time: time + 0.04)
    }

    func testTapsKeepPointerStillAndOnlyTheSecondClickHasCountTwo() {
        var finger = FingerTrackpad<Int>()
        finger.sensitivity = 4
        XCTAssertEqual(finger.begin([1: origin], at: 1), [])
        XCTAssertNil(finger.holdDeadline)
        let wobble = Point(x: 53, y: 44)
        XCTAssertEqual(finger.move(to: wobble, at: 1.02), [])
        XCTAssertEqual(finger.end(at: wobble, time: 1.05), [.click(.left, 1)])
        XCTAssertEqual(tap(&finger, at: 1.2, point: origin), [.click(.left, 2)])
        XCTAssertEqual(tap(&finger, at: 1.3, point: origin), [.click(.left, 1)])
    }

    func testRelativeMovementUsesSensitivityAndReanchorsOnEveryTouchdown() {
        var finger = FingerTrackpad<Int>()
        finger.sensitivity = 2
        _ = finger.begin([1: .zero], at: 1)
        XCTAssertEqual(finger.move(to: Point(x: 3, y: 0), at: 1.01), [])
        XCTAssertEqual(finger.move(to: Point(x: 8, y: -2), at: 1.02), [.relative(Point(x: 10, y: -4))])
        XCTAssertEqual(finger.move(to: .zero, at: 1.03), [.relative(Point(x: -16, y: 4))])
        XCTAssertEqual(finger.end(at: .zero, time: 1.04), [])
        _ = finger.begin([2: origin], at: 2)
        XCTAssertEqual(finger.end(at: Point(x: 60, y: 40), time: 2.08), [.relative(Point(x: 20, y: 0))])
    }

    func testHoldingTheSecondTapStartsOneDragAndLiftingReleasesAtTheFinalPosition() throws {
        var finger = FingerTrackpad<Int>()
        var mouse = InputState()
        mouse.syncCursor(origin)
        _ = tap(&finger, at: 1, point: origin)
        _ = finger.begin([2: origin], at: 1.2)
        let deadline = try XCTUnwrap(finger.holdDeadline)
        XCTAssertEqual(finger.hold(at: deadline - 0.01), [])
        XCTAssertEqual(finger.hold(at: deadline).flatMap { mouse.apply($0) }, [.down(.left, origin, clickCount: 1)])
        XCTAssertEqual(finger.hold(at: deadline + 0.1), [])
        let final = Point(x: 56, y: 42)
        let destination = Point(x: 59, y: 43)
        XCTAssertEqual(finger.end(at: final, time: deadline + 0.2).flatMap { mouse.apply($0) },
                       [.move(destination, dragging: true), .up(.left, destination, clickCount: 1)])
        XCTAssertFalse(mouse.leftHeld)
        XCTAssertNil(finger.activeTouch)
    }

    func testSlidingTheSecondTouchPressesBeforeMovingWithoutWaitingForTheTimer() {
        var finger = FingerTrackpad<Int>()
        _ = tap(&finger, at: 1, point: origin)
        _ = finger.begin([2: origin], at: 1.2)
        let next = Point(x: 60, y: 40)
        XCTAssertEqual(finger.move(to: next, at: 1.21), [.drag(true), .relative(Point(x: 15, y: 0))])
        XCTAssertNil(finger.holdDeadline)
        XCTAssertEqual(finger.end(at: next, time: 1.22), [.drag(false)])
        XCTAssertEqual(finger.hold(at: 2), [])
    }

    func testRestingFingerAndSeparatedTapsDoNotArmDrags() {
        var finger = FingerTrackpad<Int>()
        _ = finger.begin([1: origin], at: 1)
        XCTAssertEqual(finger.hold(at: 2), [])
        XCTAssertEqual(finger.end(at: origin, time: 2), [])
        XCTAssertEqual(tap(&finger, at: 2.1, point: origin), [.click(.left, 1)])
        XCTAssertEqual(tap(&finger, at: 2.2, point: .zero), [.click(.left, 1)])
        XCTAssertEqual(tap(&finger, at: 3, point: .zero), [.click(.left, 1)])
    }

    func testSecondFingerReleasesDragAndLeftoverTouchCannotClickOrMove() {
        var finger = FingerTrackpad<Int>()
        _ = tap(&finger, at: 1, point: origin)
        _ = finger.begin([2: origin], at: 1.1)
        XCTAssertEqual(finger.hold(at: 1.5), [.drag(true)])
        XCTAssertEqual(finger.begin([2: origin, 3: .zero], at: 1.6), [.drag(false)])
        XCTAssertNil(finger.activeTouch)
        XCTAssertEqual(finger.move(to: .zero, at: 1.7), [])
        XCTAssertEqual(finger.end(at: .zero, time: 1.8), [])
        XCTAssertEqual(tap(&finger, at: 1.9, point: .zero), [.click(.left, 1)])
    }

    func testInterruptionDiscardsTapHistoryAndADeferredHoldAndReleasesAnActiveDragOnce() {
        var finger = FingerTrackpad<Int>()
        _ = tap(&finger, at: 1, point: origin)
        _ = finger.begin([2: origin], at: 1.1)
        XCTAssertEqual(finger.interrupt(), [])
        XCTAssertEqual(finger.hold(at: 1.5), [])
        XCTAssertEqual(finger.end(at: origin, time: 1.6), [])
        XCTAssertEqual(tap(&finger, at: 2, point: origin), [.click(.left, 1)])
        _ = finger.begin([3: origin], at: 2.2)
        _ = finger.hold(at: 2.5)
        XCTAssertEqual(finger.interrupt(), [.drag(false)])
        XCTAssertEqual(finger.interrupt(), [])
    }

    func testStaleSamplesAreIgnoredAndInvalidTerminalInputReleasesHeldButton() {
        var finger = FingerTrackpad<Int>()
        _ = tap(&finger, at: 1, point: origin)
        _ = finger.begin([2: origin], at: 1.1)
        XCTAssertEqual(finger.move(to: .zero, at: 1.05), [])
        _ = finger.hold(at: 1.4)
        XCTAssertEqual(finger.end(at: origin, time: .nan), [.drag(false)])
        XCTAssertEqual(finger.hold(at: 2), [])
        XCTAssertEqual(finger.begin([1: Point(x: .nan, y: 0)], at: 2), [])
        XCTAssertNil(finger.activeTouch)
    }
}

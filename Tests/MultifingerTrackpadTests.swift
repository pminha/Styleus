import XCTest
@testable import StyleusCore

final class MultifingerTrackpadTests: XCTestCase {
    private let pair = [1: Point(x: 30, y: 60), 2: Point(x: 90, y: 60)]
    private let triple = [1: Point(x: 30, y: 60), 2: Point(x: 90, y: 60), 3: Point(x: 150, y: 90)]

    private func shifted(_ positions: [Int: Point], x: Double, y: Double = 0) -> [Int: Point] {
        positions.mapValues { Point(x: $0.x + x, y: $0.y + y) }
    }

    func testTwoFingerTapProducesOneRightClickAtTheCurrentPointerOnLastLift() {
        for firstLift in [1, 2] {
            var finger = FingerTrackpad<Int>()
            var mouse = InputState()
            let cursor = Point(x: 450, y: 700)
            mouse.syncCursor(cursor)
            XCTAssertEqual(finger.begin([1: pair[1]!], at: 1, onEmptySurface: true), [])
            XCTAssertEqual(finger.begin(pair, at: 1.04, onEmptySurface: false), [])
            let wobble = shifted(pair, x: 1, y: 1)
            XCTAssertEqual(finger.moveGroup(wobble, at: 1.06), [])
            XCTAssertEqual(finger.end(wobble, remaining: 1, at: 1.08), [])
            let remaining = wobble.filter { $0.key != firstLift }
            let actions = finger.end(remaining, remaining: 0, at: 1.1)
            XCTAssertEqual(actions, [.click(.right, 1)])
            XCTAssertEqual(actions.flatMap { mouse.apply($0) },
                           [.down(.right, cursor, clickCount: 1), .up(.right, cursor, clickCount: 1)])
            XCTAssertEqual(finger.end(remaining, remaining: 0, at: 1.12), [])
        }
    }

    func testSimultaneousPairsAndAdjacentSingleTapsKeepIndependentClickCounts() {
        var finger = FingerTrackpad<Int>()
        let single = [1: pair[1]!]
        _ = finger.begin(single, at: 1, onEmptySurface: true)
        XCTAssertEqual(finger.end(single, remaining: 0, at: 1.03), [.click(.left, 1)])
        for time in [1.06, 1.12] {
            _ = finger.begin(pair, at: time, onEmptySurface: true)
            XCTAssertEqual(finger.end(pair, remaining: 0, at: time + 0.03), [.click(.right, 1)])
        }
        _ = finger.begin(single, at: 1.2, onEmptySurface: true)
        XCTAssertEqual(finger.end(single, remaining: 0, at: 1.23), [.click(.left, 1)])
    }

    func testTapUsesEachFingersTravelThroughItsFinalSample() {
        var finger = FingerTrackpad<Int>()
        var spread = pair
        spread[1]!.x -= 12
        spread[2]!.x += 12
        _ = finger.begin(pair, at: 1, onEmptySurface: true)
        _ = finger.moveGroup(spread, at: 1.02)
        _ = finger.moveGroup(pair, at: 1.04)
        XCTAssertEqual(finger.end(pair, remaining: 0, at: 1.06), [])
        _ = finger.begin(pair, at: 2, onEmptySurface: true)
        XCTAssertEqual(finger.end(spread, remaining: 0, at: 2.03), [])
        _ = finger.begin(pair, at: 3, onEmptySurface: true)
        _ = finger.end(pair, remaining: 1, at: 3.03)
        XCTAssertEqual(finger.end([1: spread[1]!], remaining: 0, at: 3.06), [])
    }

    func testHeldFingerOrReplacedFingerCannotCompleteATwoFingerTap() {
        var finger = FingerTrackpad<Int>()
        let first = [1: pair[1]!]
        _ = finger.begin(first, at: 1, onEmptySurface: true)
        _ = finger.begin(pair, at: 1.3, onEmptySurface: false)
        XCTAssertEqual(finger.end(pair, remaining: 0, at: 1.4), [])
        _ = finger.begin(pair, at: 2, onEmptySurface: true)
        _ = finger.end(pair, remaining: 1, at: 2.02)
        let replacement = [1: pair[1]!, 3: pair[2]!]
        XCTAssertEqual(finger.begin(replacement, at: 2.04, onEmptySurface: false), [])
        XCTAssertEqual(finger.end(replacement, remaining: 0, at: 2.06), [])
    }

    func testThreeFingerDragPressesBeforeRelativeTravelAndFlushesFinalTravelBeforeRelease() {
        var finger = FingerTrackpad<Int>()
        finger.sensitivity = 2
        var mouse = InputState()
        let cursor = Point(x: 400, y: 200)
        mouse.syncCursor(cursor)
        XCTAssertEqual(finger.begin(triple, at: 1, onEmptySurface: true), [])
        XCTAssertNil(finger.holdDeadline)
        XCTAssertEqual(finger.moveGroup(shifted(triple, x: 2), at: 1.02), [])
        let start = finger.moveGroup(shifted(triple, x: 9, y: -3), at: 1.04)
        XCTAssertEqual(start, [.drag(true), .relative(Point(x: 18, y: -6))])
        XCTAssertEqual(start.flatMap { mouse.apply($0) },
                       [.down(.left, cursor, clickCount: 1), .move(Point(x: 418, y: 194), dragging: true)])
        let travel = finger.moveGroup(shifted(triple, x: 12, y: -6), at: 1.06)
        XCTAssertEqual(travel, [.relative(Point(x: 6, y: -6))])
        _ = travel.flatMap { mouse.apply($0) }
        let lift = finger.end(shifted(triple, x: 15, y: -6), remaining: 2, at: 1.08)
        let destination = Point(x: 430, y: 188)
        XCTAssertEqual(lift.flatMap { mouse.apply($0) },
                       [.move(destination, dragging: true), .up(.left, destination, clickCount: 1)])
        XCTAssertFalse(mouse.leftHeld)
        XCTAssertEqual(finger.end(pair, remaining: 0, at: 1.1), [])

        // A fast slide can deliver its first movement on the lift itself.
        _ = finger.begin(triple, at: 2, onEmptySurface: true)
        XCTAssertEqual(finger.end(shifted(triple, x: 9), remaining: 0, at: 2.03),
                       [.drag(true), .relative(Point(x: 18, y: 0)), .drag(false)])
    }

    func testThreeFingersCanLandInStagesAfterPositioningThePointer() {
        var finger = FingerTrackpad<Int>()
        finger.sensitivity = 1
        _ = finger.begin([1: .zero], at: 1, onEmptySurface: true)
        XCTAssertEqual(finger.move(to: pair[1]!, at: 1.02), [.relative(pair[1]!)])
        XCTAssertEqual(finger.begin(pair, at: 1.04, onEmptySurface: false), [])
        XCTAssertEqual(finger.begin(triple, at: 1.08, onEmptySurface: false), [])
        var uneven = triple
        uneven[1]!.x += 6
        uneven[2]!.x += 12
        uneven[3]!.x += 18
        XCTAssertEqual(finger.moveGroup(uneven, at: 1.1), [.drag(true), .relative(Point(x: 12, y: 0))])
        XCTAssertEqual(finger.end(uneven, remaining: 0, at: 1.12), [.drag(false)])
        _ = finger.begin([1: .zero], at: 2, onEmptySurface: true)
        _ = finger.move(to: pair[1]!, at: 2.02)
        _ = finger.begin(pair, at: 2.04, onEmptySurface: false)
        XCTAssertEqual(finger.end(pair, remaining: 0, at: 2.08), [])
    }

    func testThreeFingerRestAndPartialLiftNeverClickOrRearmFromRemainingContacts() {
        var finger = FingerTrackpad<Int>()
        _ = finger.begin(triple, at: 1, onEmptySurface: true)
        XCTAssertEqual(finger.hold(at: 1.4), [])
        XCTAssertEqual(finger.end(shifted(triple, x: 1), remaining: 2, at: 1.5), [])
        XCTAssertEqual(finger.moveGroup(shifted(pair, x: 20), at: 1.6), [])
        XCTAssertEqual(finger.begin(triple, at: 1.65, onEmptySurface: false), [])
        XCTAssertEqual(finger.moveGroup(shifted(triple, x: 20), at: 1.7), [])
        XCTAssertEqual(finger.end(triple, remaining: 0, at: 1.8), [])
        _ = finger.begin(pair, at: 2, onEmptySurface: true)
        XCTAssertEqual(finger.end(pair, remaining: 0, at: 2.04), [.click(.right, 1)])
    }

    func testFourthFingerAndPencilOrSessionInterruptionReleaseTheDragExactlyOnce() {
        var finger = FingerTrackpad<Int>()
        for fourthFinger in [true, false] {
            _ = finger.begin(triple, at: 1, onEmptySurface: true)
            _ = finger.moveGroup(shifted(triple, x: 12), at: 1.1)
            let four = triple.merging([4: Point.zero]) { old, _ in old }
            let release = fourthFinger ? finger.begin(four, at: 1.12, onEmptySurface: false) : finger.interrupt()
            XCTAssertEqual(release, [.drag(false)])
            XCTAssertEqual(finger.interrupt(), [])
            XCTAssertEqual(finger.begin(triple, at: 1.14, onEmptySurface: false), [])
            XCTAssertEqual(finger.moveGroup(shifted(triple, x: 15), at: 1.16), [])
        }
    }

    func testBadSamplesAndChangedTouchIdentityCannotLeaveAThreeFingerDragHeld() {
        var finger = FingerTrackpad<Int>()
        let wrongIDs = [1: triple[1]!, 2: triple[2]!, 4: triple[3]!]
        var invalid = triple
        invalid[3]!.x = .nan
        for positions in [wrongIDs, invalid, shifted(triple, x: 10_000)] {
            _ = finger.begin(triple, at: 1, onEmptySurface: true)
            _ = finger.moveGroup(shifted(triple, x: 12), at: 1.1)
            XCTAssertEqual(finger.moveGroup(triple, at: 1.05), [])
            XCTAssertEqual(finger.moveGroup(positions, at: 1.12), [.drag(false)])
            XCTAssertEqual(finger.end(triple, remaining: 0, at: 1.2), [])
        }
    }
}

import XCTest
@testable import StyleusCore

final class ScrollGestureTests: XCTestCase {
    private func pair(x: Double = 0, y: Double = 0) -> [Int: Point] {
        [1: Point(x: x, y: y), 2: Point(x: x + 40, y: y)]
    }

    func testOnlyTwoFingerMotionScrollsWithoutMovingOrClickingPointer() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        XCTAssertEqual(scroll.update([1: .zero], at: 1), [])
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 200)], at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 200), at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 202), at: 1), [])
        let deltas = scroll.update(pair(x: 5, y: 210), at: 1)
        XCTAssertEqual(deltas, [Point(x: 5, y: 10)])
        for mode in InputMode.allCases {
            var mouse = InputState()
            _ = mouse.apply(.mode(mode))
            mouse.syncCursor(Point(x: 100, y: 200))
            let sample = ScrollSample(delta: deltas[0], phase: .began)
            XCTAssertEqual(mouse.apply(.scroll(sample)), [.scroll(sample)])
            XCTAssertEqual(mouse.cursor, Point(x: 100, y: 200))
            XCTAssertFalse(mouse.leftHeld)
        }
        XCTAssertEqual(scroll.update([:], at: 1), [])
        XCTAssertFalse(scroll.active)
    }

    func testAddingLiftingAndReplacingFingersReanchorsWithoutJump() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        _ = scroll.update(pair(), at: 1)
        _ = scroll.update(pair(y: 10), at: 1)
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 10)], at: 1), [])
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 500)], at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 500), at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 510), at: 1), [Point(x: 0, y: 10)])
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 510), 3: Point(x: 400, y: 900)], at: 1), [])
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 520), 3: Point(x: 400, y: 910)], at: 1), [Point(x: 0, y: 10)])
    }

    func testPencilSuppressesRestingFingersUntilTheyAllLift() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        _ = scroll.update(pair(), at: 1)
        _ = scroll.update(pair(y: 10), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 20), at: 1, pencilDown: true), [])
        XCTAssertFalse(scroll.active)
        XCTAssertEqual(scroll.update(pair(y: 50), at: 1), [])
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 50)], at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 100), at: 1), [])
        _ = scroll.update([:], at: 1)
        XCTAssertEqual(scroll.update(pair(y: 100), at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 110), at: 1), [Point(x: 0, y: 10)])
        _ = scroll.update([:], at: 1, pencilDown: true)
        XCTAssertEqual(scroll.update(pair(), at: 1, pencilDown: true), [])
        XCTAssertEqual(scroll.update(pair(y: 50), at: 1), [])
    }

    func testThirdFingerCancelsUntilAllContactsLift() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        _ = scroll.update(pair(), at: 1)
        _ = scroll.update(pair(y: 10), at: 1)
        var three = pair(y: 20)
        three[3] = Point(x: 80, y: 20)
        XCTAssertEqual(scroll.update(three, at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 30), at: 1), [])
        _ = scroll.update([:], at: 1)
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 10), at: 1), [Point(x: 0, y: 10)])
    }

    func testInterruptionDiscardsMotionAndRequiresLiftBeforeRestart() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        _ = scroll.update(pair(), at: 1)
        _ = scroll.update(pair(y: 10), at: 1)
        scroll.interrupt() // Mode, rotation, settings, cancellation, or disconnect.
        XCTAssertFalse(scroll.active)
        XCTAssertEqual(scroll.update(pair(y: 200), at: 1), [])
        _ = scroll.update([:], at: 1)
        _ = scroll.update(pair(y: 300), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 304), at: 1), [Point(x: 0, y: 4)])
        _ = scroll.update([:], at: 1)
        scroll.interrupt() // No contacts: the next fresh gesture can start immediately.
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 4), at: 1), [Point(x: 0, y: 4)])
    }

    func testNaturalDirectionAndFractionalTravelArePreserved() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        scroll.reverseVertical = true
        scroll.reverseHorizontal = true
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(x: 4, y: 8), at: 1), [Point(x: -4, y: -8)])
        for offset in [0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(scroll.update(pair(x: 4 + offset, y: 8 + offset), at: 1), [Point(x: -0.25, y: -0.25)])
        }
        _ = scroll.update(pair(x: 5.5, y: 9.5), at: 1)
        _ = scroll.update([:], at: 1)
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(x: 4, y: 8), at: 1), [Point(x: -4, y: -8)])
    }

    func testInvalidAndImplausibleMotionCannotScrollOrResume() {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.acceleratesWithSpeed = false
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update([1: Point(x: .nan, y: 0), 2: .zero], at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 20), at: 1), [])
        _ = scroll.update([:], at: 1)
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 3000), at: 1), [])
        XCTAssertEqual(scroll.update(pair(y: 3010), at: 1), [])
        _ = scroll.update([:], at: 1)
        _ = scroll.update(pair(), at: 1)
        XCTAssertEqual(scroll.update(pair(y: 5), at: 1), [Point(x: 0, y: 5)])
    }

    func testDirectionsCanReverseIndependently() {
        for vertical in [false, true] {
            for horizontal in [false, true] {
                var scroll = TwoFingerScrollInterpreter<Int>()
                scroll.acceleratesWithSpeed = false
                scroll.reverseVertical = vertical
                scroll.reverseHorizontal = horizontal
                _ = scroll.update(pair(), at: 1)
                XCTAssertEqual(scroll.update(pair(x: 10, y: 20), at: 1),
                               [Point(x: horizontal ? -10 : 10, y: vertical ? -20 : 20)])
            }
        }
    }

    func testScrollSensitivityScalesDistanceWithoutChangingRecognition() {
        for sensitivity in [0.25, 1, 2, 4] {
            var scroll = TwoFingerScrollInterpreter<Int>()
            scroll.acceleratesWithSpeed = false
            scroll.sensitivity = sensitivity
            _ = scroll.update(pair(), at: 1)
            XCTAssertEqual(scroll.update(pair(y: 3), at: 1), [])
            XCTAssertEqual(scroll.update(pair(x: 4, y: 8), at: 1), [Point(x: 4 * sensitivity, y: 8 * sensitivity)])
            XCTAssertEqual(scroll.update(pair(x: 4.5, y: 8.5), at: 1), [Point(x: 0.5 * sensitivity, y: 0.5 * sensitivity)])
        }
    }
}

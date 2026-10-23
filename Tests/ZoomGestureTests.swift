import XCTest
@testable import StyleusCore

final class ZoomGestureTests: XCTestCase {
    private func pair(span: Double = 100, x: Double = 200, y: Double = 200) -> [Int: Point] {
        [1: Point(x: x - span / 2, y: y), 2: Point(x: x + span / 2, y: y)]
    }

    private func enabled() -> TwoFingerGestureInterpreter<Int> {
        var result = TwoFingerGestureInterpreter<Int>()
        result.pinchZoomEnabled = true
        result.acceleratesWithSpeed = false
        return result
    }

    private func factor(_ samples: [ZoomSample]) -> Double {
        samples.filter { $0.phase == .changed }.reduce(1) { $0 * (1 + $1.magnification) }
    }

    func testWireSamplesBoundMagnitudeAndRequireZeroTerminalDeltas() {
        for phase in ZoomPhase.allCases {
            XCTAssertTrue(ZoomSample(phase: phase).isValid)
            for invalid in [Double.nan, .infinity, -.infinity, -1, -0.500001, 0.500001] {
                XCTAssertFalse(ZoomSample(magnification: invalid, phase: phase).isValid)
            }
            XCTAssertEqual(ZoomSample(magnification: 0.1, phase: phase).isValid, phase == .changed)
        }
        XCTAssertTrue(ZoomSample(magnification: -0.5, phase: .changed).isValid)
        XCTAssertTrue(ZoomSample(magnification: 0.5, phase: .changed).isValid)
    }

    func testDisabledZoomPreservesExistingScrollResponseAndFingerChanges() {
        for accelerates in [false, true] {
            var original = TwoFingerScrollInterpreter<Int>()
            var combined = TwoFingerGestureInterpreter<Int>()
            original.acceleratesWithSpeed = accelerates; combined.acceleratesWithSpeed = accelerates
            original.reverseVertical = true; combined.reverseVertical = true
            original.reverseHorizontal = true; combined.reverseHorizontal = true
            original.sensitivity = 2.5; combined.sensitivity = 2.5
            var snapshots: [[Int: Point]] = [[:], [1: .zero], pair(), pair(span: 120), pair(span: 120, y: 210)]
            snapshots += [pair(span: 140, x: 230, y: 240), [1: Point(x: 30, y: 90)]]
            snapshots += [[1: Point(x: 30, y: 90), 3: Point(x: 70, y: 90)],
                          [1: Point(x: 30, y: 100), 3: Point(x: 70, y: 100)], [:]]
            for (index, touches) in snapshots.enumerated() {
                let time = 1 + Double(index) / 120
                let result = combined.update(touches, at: time)
                XCTAssertEqual(result.scrollDeltas, original.update(touches, at: time))
                XCTAssertEqual(combined.active, original.active)
                XCTAssertTrue(result.zoomSamples.isEmpty)
            }
            original.interrupt(); XCTAssertTrue(combined.interrupt().isEmpty)
            XCTAssertEqual(combined.update(pair(), at: 3).scrollDeltas, original.update(pair(), at: 3))
        }
    }

    func testTranslationUsesOriginalScrollDistanceAndStaysScrolling() {
        var gesture = enabled()
        XCTAssertEqual(gesture.update(pair(), at: 1), TwoFingerGestureUpdate())
        XCTAssertEqual(gesture.update(pair(x: 202, y: 202), at: 1.01), TwoFingerGestureUpdate())
        let start = gesture.update(pair(x: 205, y: 210), at: 1.02)
        XCTAssertEqual(start.scrollDeltas, [Point(x: 5, y: 10)])
        XCTAssertTrue(start.zoomSamples.isEmpty)
        XCTAssertTrue(gesture.active)
        let lateSpread = gesture.update(pair(span: 150, x: 205, y: 220), at: 1.03)
        XCTAssertEqual(lateSpread.scrollDeltas, [Point(x: 0, y: 10)])
        XCTAssertTrue(lateSpread.zoomSamples.isEmpty)
        XCTAssertFalse(gesture.zoomActive)
    }

    func testSpreadAndPinchEmitContinuousFactorsWithNoScrolling() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        let spread = gesture.update(pair(span: 110), at: 1.01)
        XCTAssertEqual(spread.zoomSamples.first, ZoomSample(phase: .began))
        XCTAssertEqual(factor(spread.zoomSamples), 1.1, accuracy: 0.0000001)
        XCTAssertTrue(spread.scrollDeltas.isEmpty)
        XCTAssertTrue(gesture.zoomActive)
        XCTAssertFalse(gesture.active)
        let reverse = gesture.update(pair(span: 90, x: 230, y: 260), at: 1.02)
        XCTAssertEqual(factor(reverse.zoomSamples), 90.0 / 110, accuracy: 0.0000001)
        XCTAssertTrue(reverse.scrollDeltas.isEmpty)
        XCTAssertEqual(reverse.zoomSamples.count, 1)
        XCTAssertTrue(gesture.zoomActive)
        XCTAssertEqual(gesture.update([:], at: 1.03).zoomSamples, [ZoomSample(phase: .ended)])
        XCTAssertFalse(gesture.zoomActive)
        XCTAssertEqual(gesture.update([:], at: 1.04), TwoFingerGestureUpdate())
    }

    func testMixedMotionChoosesOneWinnerAndCannotSwitchMidGesture() {
        var mostlyPinch = enabled()
        _ = mostlyPinch.update(pair(), at: 1)
        let pinch = mostlyPinch.update(pair(span: 118, x: 208), at: 1.01)
        XCTAssertEqual(pinch.zoomSamples.first?.phase, .began)
        XCTAssertTrue(pinch.scrollDeltas.isEmpty)
        XCTAssertTrue(mostlyPinch.update(pair(span: 118, x: 260), at: 1.02).scrollDeltas.isEmpty)

        var mostlyScroll = enabled()
        _ = mostlyScroll.update(pair(), at: 1)
        let scroll = mostlyScroll.update(pair(span: 112, x: 220), at: 1.01)
        XCTAssertEqual(scroll.scrollDeltas, [Point(x: 20, y: 0)])
        XCTAssertTrue(scroll.zoomSamples.isEmpty)
        XCTAssertTrue(mostlyScroll.update(pair(span: 170, x: 220), at: 1.02).zoomSamples.isEmpty)
    }

    func testOneFingerLiftEndsZoomAndRequiresEntireHandToLift() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        _ = gesture.update(pair(span: 110), at: 1.01)
        XCTAssertEqual(gesture.update([1: Point(x: 145, y: 200)], at: 1.02).zoomSamples,
                       [ZoomSample(phase: .ended)])
        XCTAssertEqual(gesture.update(pair(span: 150, y: 300), at: 1.03), TwoFingerGestureUpdate())
        XCTAssertEqual(gesture.update(pair(span: 190, y: 350), at: 1.04), TwoFingerGestureUpdate())
        _ = gesture.update([:], at: 1.05)
        _ = gesture.update(pair(), at: 2)
        XCTAssertEqual(gesture.update(pair(y: 210), at: 2.01).scrollDeltas, [Point(x: 0, y: 10)])
    }

    func testReplacingZoomFingerCancelsRatherThanReanchoringAsScroll() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        _ = gesture.update(pair(span: 110), at: 1.01)
        let replacement = [1: Point(x: 145, y: 200), 3: Point(x: 300, y: 200)]
        XCTAssertEqual(gesture.update(replacement, at: 1.02).zoomSamples, [ZoomSample(phase: .cancelled)])
        XCTAssertEqual(gesture.update(pair(y: 230), at: 1.03), TwoFingerGestureUpdate())
        XCTAssertFalse(gesture.active)
        XCTAssertFalse(gesture.zoomActive)
    }

    func testPencilAndThirdFingerCancelAndSuppressRestingHand() {
        for pencil in [true, false] {
            var gesture = enabled()
            _ = gesture.update(pair(), at: 1)
            _ = gesture.update(pair(span: 110), at: 1.01)
            var contacts = pair(span: 115)
            if !pencil { contacts[3] = Point(x: 500, y: 500) }
            XCTAssertEqual(gesture.update(contacts, at: 1.02, pencilDown: pencil).zoomSamples,
                           [ZoomSample(phase: .cancelled)])
            XCTAssertEqual(gesture.update(pair(span: 180, y: 400), at: 1.03), TwoFingerGestureUpdate())
            _ = gesture.update([:], at: 1.04)
            _ = gesture.update(pair(), at: 1.05)
            XCTAssertEqual(gesture.update(pair(span: 110), at: 1.06).zoomSamples.first?.phase, .began)
        }
    }

    func testInterruptionCancelsOnceAndRequiresFreshContacts() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        _ = gesture.update(pair(span: 110), at: 1.01)
        XCTAssertEqual(gesture.interrupt(), [ZoomSample(phase: .cancelled)])
        XCTAssertEqual(gesture.interrupt(), [])
        XCTAssertEqual(gesture.update(pair(span: 180), at: 1.02), TwoFingerGestureUpdate())
        _ = gesture.update([:], at: 1.03)
        _ = gesture.update(pair(), at: 2)
        XCTAssertEqual(gesture.update(pair(span: 110), at: 2.01).zoomSamples.first?.phase, .began)
    }

    func testTooCloseFingersCanStillScrollButCannotStartUnstableZoom() {
        var gesture = enabled()
        _ = gesture.update(pair(span: 20), at: 1)
        XCTAssertEqual(gesture.update(pair(span: 30), at: 1.01), TwoFingerGestureUpdate())
        XCTAssertEqual(gesture.update(pair(span: 30, y: 210), at: 1.02).scrollDeltas, [Point(x: 0, y: 10)])

        var pinch = enabled()
        _ = pinch.update(pair(span: 40), at: 1)
        _ = pinch.update(pair(span: 34), at: 1.01)
        XCTAssertEqual(pinch.update(pair(span: 15), at: 1.02).zoomSamples, [ZoomSample(phase: .cancelled)])
    }

    func testInvalidCoordinatesAndImpossibleJumpsCancelZoom() {
        for invalid in [[1: Point(x: .nan, y: 200), 2: Point(x: 300, y: 200)],
                        pair(span: 120, x: 5000), pair(span: 400)] {
            var gesture = enabled()
            _ = gesture.update(pair(), at: 1)
            _ = gesture.update(pair(span: 110), at: 1.01)
            XCTAssertEqual(gesture.update(invalid, at: 1.02).zoomSamples, [ZoomSample(phase: .cancelled)])
            XCTAssertEqual(gesture.update(pair(span: 150), at: 1.03), TwoFingerGestureUpdate())
        }
    }

    func testOldTimestampCannotAlterTheNextZoomFactor() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        let first = gesture.update(pair(span: 110), at: 1.1)
        XCTAssertEqual(gesture.update(pair(span: 150), at: 1.05), TwoFingerGestureUpdate())
        let next = gesture.update(pair(span: 121), at: 1.2)
        XCTAssertEqual(factor(first.zoomSamples + next.zoomSamples), 1.21, accuracy: 0.0000001)
    }

    func testFastExpansionSplitsBoundedSamplesWithoutLosingScale() {
        var gesture = enabled()
        _ = gesture.update(pair(), at: 1)
        let update = gesture.update(pair(span: 180), at: 1.01)
        XCTAssertEqual(update.zoomSamples.map(\.phase), [.began, .changed, .changed])
        XCTAssertTrue(update.zoomSamples.allSatisfy(\.isValid))
        XCTAssertEqual(factor(update.zoomSamples), 1.8, accuracy: 0.0000001)
    }

    func testSamplingRateAndScrollSettingsDoNotChangeNetZoom() {
        for hz in [60, 120] {
            var gesture = enabled()
            gesture.sensitivity = 4
            gesture.reverseVertical = true
            gesture.reverseHorizontal = true
            _ = gesture.update(pair(), at: 1)
            var samples: [ZoomSample] = []
            for step in 1...hz {
                let progress = Double(step) / Double(hz)
                let update = gesture.update(pair(span: 100 + 50 * progress), at: 1 + progress)
                XCTAssertTrue(update.scrollDeltas.isEmpty)
                samples += update.zoomSamples
            }
            samples += gesture.update([:], at: 2.01).zoomSamples
            XCTAssertEqual(samples.filter { $0.phase == .began }.count, 1)
            XCTAssertEqual(samples.last?.phase, .ended)
            XCTAssertTrue(samples.allSatisfy(\.isValid))
            XCTAssertEqual(factor(samples), 1.5, accuracy: 0.0000001)
        }
    }

    func testPencilFirstDoesNotPromotePalmToZoomAfterPencilLifts() {
        var gesture = enabled()
        _ = gesture.update([:], at: 1, pencilDown: true)
        _ = gesture.update(pair(), at: 1.01, pencilDown: true)
        XCTAssertEqual(gesture.update(pair(span: 150), at: 1.02), TwoFingerGestureUpdate())
        _ = gesture.update([:], at: 1.03)
        _ = gesture.update(pair(), at: 1.04)
        XCTAssertEqual(gesture.update(pair(span: 110), at: 1.05).zoomSamples.first?.phase, .began)
    }
}

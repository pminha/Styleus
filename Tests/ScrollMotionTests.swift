import XCTest
import AppKit
@testable import StyleusCore

final class ScrollMotionTests: XCTestCase {
    private func flick() -> ScrollMotion {
        var motion = ScrollMotion()
        motion.move(Point(x: 0, y: 10), at: 1)
        _ = motion.tick(at: 1.001)
        motion.move(Point(x: 0, y: 10), at: 1.02)
        _ = motion.tick(at: 1.021)
        return motion
    }

    func testDisplayFramesCoalesceUpdatesWithoutLosingTravel() {
        var motion = ScrollMotion()
        motion.move(Point(x: 1, y: 2), at: 1)
        motion.move(Point(x: 2, y: 4), at: 1.005)
        XCTAssertEqual(motion.tick(at: 1.01), [ScrollSample(delta: Point(x: 3, y: 6), phase: .began)])
        XCTAssertEqual(motion.tick(at: 1.02), [])
        motion.move(Point(x: -1, y: 8), at: 1.025)
        XCTAssertEqual(motion.tick(at: 1.03), [ScrollSample(delta: Point(x: -1, y: 8), phase: .changed)])
        XCTAssertEqual(motion.end(at: 1.2, allFingersUp: true), [ScrollSample(phase: .ended)])
        XCTAssertFalse(motion.needsFrames)
    }

    func testFlickProducesDecayingBoundedMomentumAndEnds() {
        var motion = flick()
        XCTAssertEqual(motion.end(at: 1.025, allFingersUp: true),
                       [ScrollSample(phase: .ended), ScrollSample(phase: .momentumBegan)])
        var previous = Double.infinity
        var distance = 0.0
        var ended = false
        for frame in 1...125 {
            for sample in motion.tick(at: 1.025 + Double(frame) / 60) {
                if sample.phase == .momentumEnded { ended = true }
                else {
                    XCTAssertEqual(sample.phase, .momentumChanged)
                    XCTAssertGreaterThan(sample.delta.y, 0)
                    XCTAssertLessThan(sample.delta.y, previous)
                    previous = sample.delta.y
                    distance += sample.delta.y
                }
            }
        }
        XCTAssertTrue(ended)
        XCTAssertGreaterThan(distance, 20)
        XCTAssertLessThan(distance, 1000)
        XCTAssertFalse(motion.needsFrames)
        XCTAssertEqual(motion.tick(at: 5), [])
    }

    func testSplitFingerLiftStartsMomentumOnlyWithinGracePeriod() {
        var fast = flick()
        XCTAssertEqual(fast.end(at: 1.025, allFingersUp: false), [ScrollSample(phase: .ended)])
        XCTAssertFalse(fast.needsFrames)
        XCTAssertEqual(fast.liftRemainingFingers(at: 1.05), [ScrollSample(phase: .momentumBegan)])
        var slow = flick()
        _ = slow.end(at: 1.025, allFingersUp: false)
        XCTAssertEqual(slow.liftRemainingFingers(at: 1.2), [])
        XCTAssertFalse(slow.needsFrames)
    }

    func testNewContactOrInterruptionStopsMomentumWithoutReplay() {
        var motion = flick()
        _ = motion.end(at: 1.025, allFingersUp: true)
        XCTAssertEqual(motion.cancel(), [ScrollSample(phase: .momentumEnded)])
        XCTAssertEqual(motion.tick(at: 1.05), [])
        motion.move(Point(x: 3, y: 4), at: 2)
        XCTAssertEqual(motion.tick(at: 2.01), [ScrollSample(delta: Point(x: 3, y: 4), phase: .began)])
        XCTAssertEqual(motion.cancel(), [ScrollSample(phase: .cancelled)])
        XCTAssertEqual(motion.tick(at: 2.02), [])
    }

    func testStalledFramesDiscardOldInputRatherThanCatchingUp() {
        var motion = ScrollMotion()
        motion.move(Point(x: 0, y: 10), at: 1)
        XCTAssertEqual(motion.tick(at: 1.3), [])
        XCTAssertFalse(motion.needsFrames)
        motion = flick()
        _ = motion.end(at: 1.025, allFingersUp: true)
        XCTAssertEqual(motion.tick(at: 1.3), [ScrollSample(phase: .momentumEnded)])
        XCTAssertEqual(motion.tick(at: 1.31), [])
    }

    func testReceiverCancelsScrollOnPointerInputModeAndDisconnect() {
        let begin = ScrollSample(delta: Point(x: 0, y: 10), phase: .began)
        for interruption in [InputAction.cancel, .mode(.drawing), .click(.left, 1), .relative(.zero)] {
            var mouse = InputState()
            _ = mouse.apply(.scroll(begin))
            _ = mouse.apply(.scroll(ScrollSample(phase: .ended)))
            _ = mouse.apply(.scroll(ScrollSample(phase: .momentumBegan)))
            let effects = mouse.apply(interruption)
            XCTAssertEqual(effects.first, .scroll(ScrollSample(phase: .momentumEnded)))
            XCTAssertEqual(mouse.apply(.scroll(ScrollSample(delta: Point(x: 0, y: 5), phase: .momentumChanged))), [])
        }
        var held = InputState()
        _ = held.apply(.drag(true))
        XCTAssertEqual(held.apply(.scroll(begin)), [])
        XCTAssertTrue(held.leftHeld)
    }

    func testMacEventsExposeContinuousScrollAndMomentumPhases() throws {
        let expected: [(ScrollPhase, NSEvent.Phase, NSEvent.Phase)] = [
            (.began, .began, []), (.changed, .changed, []), (.ended, .ended, []),
            (.cancelled, .cancelled, []), (.momentumBegan, [], .began),
            (.momentumChanged, [], .changed), (.momentumEnded, [], .ended)
        ]
        var encoder = ScrollEventEncoder()
        for (phase, contact, momentum) in expected {
            let cg = try XCTUnwrap(encoder.event(ScrollSample(delta: .zero, phase: phase)))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertTrue(event.hasPreciseScrollingDeltas)
            XCTAssertEqual(event.phase, contact)
            XCTAssertEqual(event.momentumPhase, momentum)
        }
    }

    func testMacPixelEncodingPreservesFractionalTravelInBothAxes() throws {
        var encoder = ScrollEventEncoder()
        var sum = Point.zero
        for index in 0..<4 {
            let sample = ScrollSample(delta: Point(x: -0.25, y: 0.5), phase: index == 0 ? .began : .changed)
            let event = try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(encoder.event(sample))))
            sum = Point(x: sum.x + event.scrollingDeltaX, y: sum.y + event.scrollingDeltaY)
        }
        XCTAssertEqual(sum, Point(x: -1, y: 2))
    }

    func testScrollPhaseAndDeltaSurviveWireEncoding() throws {
        let sample = ScrollSample(delta: Point(x: -2.5, y: 12.25), phase: .momentumChanged)
        let action = InputAction.scroll(sample)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(InputAction.self, from: data), action)
    }

    func testFasterFlicksPreserveLaunchSpeedAbovePreviousCeiling() throws {
        func firstFrame(speed: Double) throws -> Double {
            var motion = ScrollMotion()
            for frame in 0..<12 {
                let time = 1 + Double(frame) / 120
                motion.move(Point(x: 0, y: speed / 120), at: time)
                _ = motion.tick(at: time)
            }
            let release = 1 + 11.0 / 120
            _ = motion.end(at: release, allFingersUp: true)
            return try XCTUnwrap(motion.tick(at: release + 1.0 / 120).first).delta.y
        }
        let fast = try firstFrame(speed: 4000)
        let faster = try firstFrame(speed: 8000)
        XCTAssertGreaterThan(fast, 30)
        XCTAssertEqual(faster / fast, 2, accuracy: 0.00001)
    }

    func testMomentumEndsBeforeAnIntermittentOnePointTail() throws {
        for rate in [60.0, 120.0] {
            var motion = flick()
            _ = motion.end(at: 1.025, allFingersUp: true)
            var encoder = ScrollEventEncoder()
            var ended = false
            for frame in 1...240 {
                for sample in motion.tick(at: 1.025 + Double(frame) / rate) {
                    if sample.phase == .momentumEnded { ended = true }
                    else {
                        XCTAssertGreaterThanOrEqual(abs(sample.delta.y), 1)
                        let event = try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(encoder.event(sample))))
                        XCTAssertGreaterThanOrEqual(abs(event.scrollingDeltaY), 1)
                    }
                }
            }
            XCTAssertTrue(ended)
            XCTAssertFalse(motion.needsFrames)
        }
    }

    func testMacWheelAndPreciseRepresentationsPreserveDistance() throws {
        var encoder = ScrollEventEncoder()
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        source.pixelsPerLine = 10
        var pointSum = Point.zero
        var lineSum = Point.zero
        for index in 0..<40 {
            let sample = ScrollSample(delta: Point(x: -0.5, y: 0.25), phase: index == 0 ? .began : .changed)
            let cg = try XCTUnwrap(encoder.event(sample, source: source))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(event.deltaX, -0.05, accuracy: 1.0 / 65536)
            XCTAssertEqual(event.deltaY, 0.025, accuracy: 1.0 / 65536)
            pointSum.x += event.scrollingDeltaX
            pointSum.y += event.scrollingDeltaY
            lineSum.x += Double(cg.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            lineSum.y += Double(cg.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        }
        XCTAssertEqual(pointSum, Point(x: -20, y: 10))
        XCTAssertEqual(lineSum, Point(x: -2, y: 1))
    }

    func testMacOutputScalesAcrossSlowAndFastFrames() throws {
        for delta in [1.0, 4, 10, 40, 100, 400] {
            var encoder = ScrollEventEncoder()
            let cg = try XCTUnwrap(encoder.event(ScrollSample(delta: Point(x: -delta, y: delta), phase: .began)))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(event.scrollingDeltaY, delta)
            XCTAssertEqual(event.scrollingDeltaX, -delta)
            XCTAssertEqual(event.deltaY, delta / 10, accuracy: 1.0 / 65536)
            XCTAssertEqual(cg.getIntegerValueField(.scrollWheelEventDeltaAxis1), Int64(delta / 10))
        }
    }
}

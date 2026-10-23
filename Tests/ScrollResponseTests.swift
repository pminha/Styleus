import XCTest
import AppKit
@testable import StyleusCore

final class ScrollResponseTests: XCTestCase {
    private func pair(_ position: Point) -> [Int: Point] {
        [1: position, 2: Point(x: position.x + 40, y: position.y)]
    }

    private func gesture(speed: Point, rate: Double = 120, sensitivity: Double = 1,
                         reverseX: Bool = false, reverseY: Bool = false) -> [ScrollSample] {
        var scroll = TwoFingerScrollInterpreter<Int>()
        scroll.sensitivity = sensitivity
        scroll.reverseHorizontal = reverseX; scroll.reverseVertical = reverseY
        var motion = ScrollMotion()
        _ = scroll.update(pair(.zero), at: 0)
        var result: [ScrollSample] = []
        for frame in 1...Int(rate * 0.2) {
            let time = Double(frame) / rate
            for delta in scroll.update(pair(Point(x: speed.x * time, y: speed.y * time)), at: time) {
                motion.move(delta, at: time)
            }
            result += motion.tick(at: time)
        }
        _ = scroll.update([:], at: 0.2)
        result += motion.end(at: 0.2, allFingersUp: true)
        result += motion.tick(at: 0.2 + 1 / rate)
        return result
    }

    private func contactDistance(_ samples: [ScrollSample]) -> Point {
        samples.filter { $0.phase == .began || $0.phase == .changed }
            .reduce(.zero) { Point(x: $0.x + $1.delta.x, y: $0.y + $1.delta.y) }
    }

    func testFineFingerMovementsRemainOneToOneAtDefaultSensitivity() {
        for speed in [20.0, 40, 80] {
            let result = contactDistance(gesture(speed: Point(x: 0, y: speed)))
            XCTAssertEqual(result.y, speed * 0.2, accuracy: 0.000001)
        }
    }

    func testFastSwipesGainTravelWithoutAnOutputSpeedCeiling() {
        let slow = contactDistance(gesture(speed: Point(x: 0, y: 500))).y
        let fast = contactDistance(gesture(speed: Point(x: 0, y: 4000))).y
        let faster = contactDistance(gesture(speed: Point(x: 0, y: 8000))).y
        XCTAssertGreaterThan(slow, 100)
        XCTAssertLessThan(slow, 220)
        XCTAssertGreaterThan(fast, 800 * 5)
        XCTAssertGreaterThan(faster, fast * 2)
        XCTAssertLessThan(faster, 1600 * 6)
    }

    func testResponseIsComparableAcrossTouchSamplingRates() {
        for speed in [100.0, 500, 1500, 5000] {
            let reference = contactDistance(gesture(speed: Point(x: 0, y: speed), rate: 240)).y
            for rate in [60.0, 120] {
                let distance = contactDistance(gesture(speed: Point(x: 0, y: speed), rate: rate)).y
                XCTAssertEqual(distance / reference, 1, accuracy: 0.02)
            }
        }
    }

    func testSensitivityAndAxisReversalApplyAfterAccelerationIncludingGlide() throws {
        let speed = Point(x: 1500, y: 2000)
        let reference = gesture(speed: speed)
        let distance = contactDistance(reference)
        let glide = try XCTUnwrap(reference.first { $0.phase == .momentumChanged }).delta
        for sensitivity in [0.25, 1, 2, 4] {
            for reverseX in [false, true] {
                for reverseY in [false, true] {
                    let result = gesture(speed: speed, sensitivity: sensitivity, reverseX: reverseX, reverseY: reverseY)
                    let contact = contactDistance(result)
                    let momentum = try XCTUnwrap(result.first { $0.phase == .momentumChanged }).delta
                    let sx = sensitivity * (reverseX ? -1 : 1)
                    let sy = sensitivity * (reverseY ? -1 : 1)
                    XCTAssertEqual(contact.x, distance.x * sx, accuracy: 0.000001)
                    XCTAssertEqual(contact.y, distance.y * sy, accuracy: 0.000001)
                    XCTAssertEqual(momentum.x, glide.x * sx, accuracy: 0.000001)
                    XCTAssertEqual(momentum.y, glide.y * sy, accuracy: 0.000001)
                }
            }
        }
    }

    func testFastSwipeAtMaximumSensitivitySurvivesReceiverAndMacEncoding() throws {
        let samples = gesture(speed: Point(x: 0, y: 6000), rate: 60, sensitivity: 4)
        var receiver = InputState()
        var encoder = ScrollEventEncoder()
        var receivedDistance = 0.0
        var expectedDistance = 0.0
        XCTAssertTrue(samples.contains { $0.delta.y > 2000 })
        for sample in samples {
            XCTAssertEqual(receiver.apply(.scroll(sample)), [.scroll(sample)])
            let cg = try XCTUnwrap(encoder.event(sample))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            expectedDistance += sample.delta.y
            receivedDistance += event.scrollingDeltaY
        }
        XCTAssertEqual(receivedDistance, expectedDistance, accuracy: 2)
        XCTAssertEqual(receiver.apply(.scroll(ScrollSample(delta: Point(x: 0, y: .infinity), phase: .momentumChanged))),
                       [.scroll(ScrollSample(phase: .momentumEnded))])
        XCTAssertNil(encoder.event(ScrollSample(delta: Point(x: 0, y: ScrollSample.maximumDelta + 1), phase: .changed)))
    }

    func testLiftsPairReplacementAndInterruptionsResetAcceleration() throws {
        for boundary in 0..<4 {
            var scroll = TwoFingerScrollInterpreter<Int>()
            _ = scroll.update(pair(.zero), at: 0)
            for frame in 1...12 {
                _ = scroll.update(pair(Point(x: 0, y: Double(frame) * 40)), at: Double(frame) / 120)
            }
            switch boundary {
            case 0: _ = scroll.update([:], at: 0.11)
            case 1: _ = scroll.update([1: .zero], at: 0.11)
            case 2: scroll.interrupt(); _ = scroll.update([:], at: 0.11)
            default:
                _ = scroll.update(pair(.zero), at: 0.11, pencilDown: true)
                XCTAssertEqual(scroll.update(pair(Point(x: 0, y: 4)), at: 0.12), [])
                _ = scroll.update([:], at: 0.13)
            }
            _ = scroll.update(pair(.zero), at: 0.14)
            XCTAssertEqual(scroll.update(pair(Point(x: 0, y: 4)), at: 0.22), [Point(x: 0, y: 4)])
        }
        var scroll = TwoFingerScrollInterpreter<Int>()
        _ = scroll.update(pair(.zero), at: 0)
        _ = scroll.update(pair(Point(x: 0, y: 100)), at: 0.02)
        _ = scroll.update([1: .zero, 3: Point(x: 40, y: 0)], at: 0.03)
        XCTAssertEqual(scroll.update([1: Point(x: 0, y: 4), 3: Point(x: 40, y: 4)], at: 0.11), [Point(x: 0, y: 4)])
    }

    func testRepeatedTimestampsAndPausesCannotCauseASpeedSpike() {
        var response = ScrollResponse()
        response.begin(at: 1)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 0.5), at: 1), 1)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 0.5), at: 1), 1)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 0.1), at: 1.02), 1)
        _ = response.gain(for: Point(x: 0, y: 100), at: 1.04)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 1), at: 2), 1)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 1), at: 2.02), 1)
        XCTAssertEqual(response.gain(for: Point(x: .nan, y: 1), at: 2.03), 1)
        XCTAssertEqual(response.gain(for: Point(x: 0, y: 1), at: 2.05), 1)
    }

    func testReversingMovementNeverContinuesInTheOldDirection() throws {
        var scroll = TwoFingerScrollInterpreter<Int>()
        _ = scroll.update(pair(.zero), at: 0)
        for frame in 1...12 {
            _ = scroll.update(pair(Point(x: 0, y: Double(frame) * 30)), at: Double(frame) / 120)
        }
        for frame in 1...12 {
            let delta = try XCTUnwrap(scroll.update(pair(Point(x: 0, y: 360 - Double(frame) * 2)),
                                                    at: 0.1 + Double(frame) / 120).first)
            XCTAssertLessThan(delta.y, 0)
        }
    }
}

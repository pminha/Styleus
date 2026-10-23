import XCTest
@testable import StyleusCore

final class PencilGestureTests: XCTestCase {
    func testTapAndDoubleTapWobbleNeverMoveCursorAtAnySensitivity() {
        for gain in [0.2, 1, 1.5, 4] {
            var pencil = PencilInterpreter()
            pencil.sensitivity = gain
            var mouse = InputState()
            let target = Point(x: 400, y: 300)
            mouse.syncCursor(target)
            for (start, count) in [(1.0, 1), (1.2, 2)] {
                _ = pencil.begin(.zero, pressure: 0.8, at: start)
                for (offset, point) in [Point(x: 3, y: 4), Point(x: -6, y: 0), Point(x: 1, y: -2)].enumerated() {
                    XCTAssertEqual(pencil.move(point, pressure: 0.8, at: start + Double(offset + 1) * 0.02), [])
                }
                let effects = pencil.end(at: start + 0.1).flatMap { mouse.apply($0) }
                XCTAssertEqual(effects, [.down(.left, target, clickCount: count), .up(.left, target, clickCount: count)])
                XCTAssertEqual(mouse.cursor, target)
            }
        }
    }

    func testLongPressWobbleStaysStillAndCancelledWobbleIsDiscarded() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, pressure: 1, at: 1)
        XCTAssertEqual(pencil.move(Point(x: 4, y: 3), pressure: 1, at: 1.6), [])
        XCTAssertEqual(pencil.end(at: 1.7), [.click(.right, 1)])
        _ = pencil.begin(.zero, at: 2)
        XCTAssertEqual(pencil.move(Point(x: 4, y: 3), at: 2.1), [])
        XCTAssertEqual(pencil.interrupt(), [.cancel])
        XCTAssertEqual(pencil.end(at: 2.2), [])
        XCTAssertEqual(pencil.begin(Point(x: 100, y: 100), at: 3), [])
        XCTAssertEqual(pencil.end(at: 3.1), [.click(.left, 1)])
    }

    func testLeavingTapAllowanceDoesNotReplayWobbleOrReenterDeadZone() {
        var pencil = PencilInterpreter()
        pencil.sensitivity = 1
        _ = pencil.begin(.zero, at: 1)
        XCTAssertEqual(pencil.move(Point(x: 5, y: 0), at: 1.1), [])
        XCTAssertEqual(pencil.move(Point(x: 7, y: 0), at: 1.2), [.relative(Point(x: 2, y: 0))])
        XCTAssertEqual(pencil.move(Point(x: 2, y: 0), at: 1.3), [.relative(Point(x: -5, y: 0))])
        XCTAssertEqual(pencil.move(Point(x: 1, y: 0), pressure: 0.8, at: 1.4), [.drag(true), .relative(Point(x: -1, y: 0))])
        XCTAssertEqual(pencil.end(at: 1.5), [.drag(false)])
    }

    func testTapClicksOnLiftAndTwoTapsProduceExactlyTwoClicks() {
        var pencil = PencilInterpreter()
        var mouse = InputState()
        XCTAssertEqual(pencil.begin(.zero, pressure: 0.8, at: 1), [])
        let first = pencil.end(at: 1.1)
        XCTAssertEqual(first, [.click(.left, 1)])
        XCTAssertEqual(pencil.begin(Point(x: 2, y: 1), pressure: 0.8, at: 1.2), [])
        let second = pencil.end(at: 1.3)
        XCTAssertEqual(second, [.click(.left, 2)])
        let events = (first + second).flatMap { mouse.apply($0) }
        XCTAssertEqual(events, [.down(.left, .zero, clickCount: 1), .up(.left, .zero, clickCount: 1),
                                .down(.left, .zero, clickCount: 2), .up(.left, .zero, clickCount: 2)])
        XCTAssertFalse(mouse.leftHeld)
    }

    func testSingleLongPressProducesOnlyRightClickOnLiftEvenWithFirmPressure() {
        var pencil = PencilInterpreter()
        XCTAssertEqual(pencil.begin(.zero, pressure: 0.8, at: 1), [])
        XCTAssertEqual(pencil.move(.zero, pressure: 0.9, at: 1.6), [])
        XCTAssertEqual(pencil.end(at: 1.7), [.click(.right, 1)])
        _ = pencil.begin(.zero, at: 1.8)
        XCTAssertEqual(pencil.end(at: 1.9), [.click(.left, 1)])
    }

    func testNavigationAndLongStationaryPauseAfterMovingNeverClick() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, pressure: 0.05, at: 1)
        XCTAssertEqual(pencil.move(Point(x: 20, y: 0), pressure: 0.05, at: 1.1), [.relative(Point(x: 30, y: 0))])
        XCTAssertEqual(pencil.end(at: 3), [])
        _ = pencil.begin(Point(x: 800, y: 500), pressure: 0.05, at: 4)
        XCTAssertEqual(pencil.move(Point(x: 810, y: 500), pressure: 0.05, at: 4.1), [.relative(Point(x: 15, y: 0))])
        XCTAssertEqual(pencil.end(at: 4.2), [])
    }

    func testPressureDragHasHysteresisAndNeverAddsTapOnLift() {
        var pencil = PencilInterpreter()
        pencil.sensitivity = 1
        pencil.pressureThreshold = 0.4
        _ = pencil.begin(.zero, pressure: 0.1, at: 1)
        _ = pencil.move(Point(x: 10, y: 0), pressure: 0.1, at: 1.1)
        XCTAssertEqual(pencil.move(Point(x: 12, y: 0), pressure: 0.5, at: 1.2), [.drag(true), .relative(Point(x: 2, y: 0))])
        XCTAssertEqual(pencil.move(Point(x: 14, y: 0), pressure: 0.35, at: 1.3), [.relative(Point(x: 2, y: 0))])
        XCTAssertEqual(pencil.move(Point(x: 16, y: 0), pressure: 0.2, at: 1.4), [.drag(false), .relative(Point(x: 2, y: 0))])
        XCTAssertEqual(pencil.end(at: 1.5), [])
        _ = pencil.begin(.zero, pressure: 0.5, at: 2)
        _ = pencil.move(Point(x: 10, y: 0), pressure: 0.5, at: 2.1)
        XCTAssertEqual(pencil.end(at: 2.2), [.drag(false)])
    }

    func testLightDrawingPositionsWithoutInkAndPressureReentryStartsSeparateStroke() {
        var pencil = PencilInterpreter()
        pencil.mode = .drawing
        pencil.surface = Rect(x: 0, y: 0, width: 100, height: 100)
        pencil.pressureThreshold = 0.4
        var mouse = InputState()
        mouse.target = Rect(x: 100, y: 200, width: 100, height: 100)
        _ = mouse.apply(.mode(.drawing))
        let light = pencil.begin(Point(x: 20, y: 20), pressure: 0.1, at: 1)
        XCTAssertEqual(light, [.position(Point(x: 0.2, y: 0.2))])
        XCTAssertEqual(light.flatMap { mouse.apply($0) }, [.move(Point(x: 120, y: 220), dragging: false)])
        let start = pencil.move(Point(x: 30, y: 30), pressure: 0.5, at: 1.1)
        XCTAssertEqual(start, [.strokeBegin(Point(x: 0.3, y: 0.3))])
        _ = start.flatMap { mouse.apply($0) }
        let release = pencil.move(Point(x: 40, y: 40), pressure: 0.2, at: 1.2)
        XCTAssertEqual(release, [.strokeEnd, .position(Point(x: 0.4, y: 0.4))])
        XCTAssertEqual(release.flatMap { mouse.apply($0) }, [.up(.left, Point(x: 130, y: 230), clickCount: 1),
                                                           .move(Point(x: 140, y: 240), dragging: false)])
        _ = pencil.move(Point(x: 80, y: 80), pressure: 0.1, at: 1.3).flatMap { mouse.apply($0) }
        let next = pencil.move(Point(x: 90, y: 90), pressure: 0.5, at: 1.4)
        XCTAssertEqual(next.flatMap { mouse.apply($0) }, [.move(Point(x: 190, y: 290), dragging: false),
                                                        .down(.left, Point(x: 190, y: 290), clickCount: 1)])
        _ = pencil.end(at: 1.5).flatMap { mouse.apply($0) }
        XCTAssertFalse(mouse.leftHeld)
    }

    func testCancelledTapCannotClickOrCompleteDoubleClick() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, at: 1); _ = pencil.end(at: 1.1)
        _ = pencil.begin(.zero, at: 1.2)
        XCTAssertEqual(pencil.interrupt(), [.cancel])
        XCTAssertEqual(pencil.move(.zero, pressure: 1, at: 1.3), [])
        XCTAssertEqual(pencil.end(at: 1.4), [])
        _ = pencil.begin(.zero, at: 1.5)
        XCTAssertEqual(pencil.end(at: 1.6), [.click(.left, 1)])
    }

    func testSeparatedOrSlowTapsRemainSingleClicks() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, at: 1); _ = pencil.end(at: 1.1)
        _ = pencil.begin(Point(x: 100, y: 100), at: 1.2)
        XCTAssertEqual(pencil.end(at: 1.3), [.click(.left, 1)])
        _ = pencil.begin(Point(x: 100, y: 100), at: 2)
        XCTAssertEqual(pencil.end(at: 2.1), [.click(.left, 1)])
    }

    func testStaleSamplesAndInvalidPressureCannotStartUnexpectedInput() {
        var pencil = PencilInterpreter()
        pencil.mode = .drawing
        pencil.surface = Rect(x: 0, y: 0, width: 100, height: 100)
        _ = pencil.begin(Point(x: 20, y: 20), pressure: 0.1, at: 1)
        XCTAssertEqual(pencil.move(Point(x: 30, y: 30), pressure: 1, at: 0.9), [])
        XCTAssertEqual(pencil.move(Point(x: 40, y: 40), pressure: .nan, at: 1.1), [.position(Point(x: 0.4, y: 0.4))])
        XCTAssertEqual(pencil.move(Point(x: .nan, y: 40), pressure: 1, at: 1.2), [.cancel])
        XCTAssertEqual(pencil.end(at: 1.3), [])
    }
}

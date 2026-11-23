import XCTest
@testable import StyleusCore

final class InputStateTests: XCTestCase {
    func testLiveCursorReadsFollowUnheldTrackpadActions() {
        var state = InputState()
        let relative = InputAction.relative(Point(x: 2, y: 3))
        for action in [relative, .click(.left, 1), .drag(true)] {
            XCTAssertTrue(state.needsCursorLocation(for: action))
        }
        for action in [InputAction.heartbeat, .cancel, .drag(false), .scroll(ScrollSample(phase: .began)),
                       .zoom(ZoomSample(phase: .began)), .position(.zero)] {
            XCTAssertFalse(state.needsCursorLocation(for: action))
        }
        _ = state.apply(.drag(true))
        XCTAssertFalse(state.needsCursorLocation(for: relative))
        _ = state.apply(.drag(false))
        XCTAssertTrue(state.needsCursorLocation(for: relative))
        _ = state.apply(.mode(.drawing))
        XCTAssertFalse(state.needsCursorLocation(for: .strokeBegin(.zero)))
        _ = state.apply(.strokeBegin(.zero))
        XCTAssertFalse(state.needsCursorLocation(for: .strokeMove(.zero)))
    }

    func testMovementLiftAndRepositionDoNotClickOrJump() {
        var pencil = PencilInterpreter()
        pencil.sensitivity = 2
        XCTAssertEqual(pencil.begin(Point(x: 50, y: 50)), [])
        XCTAssertEqual(pencil.move(Point(x: 55, y: 60)), [.relative(Point(x: 10, y: 20))])
        XCTAssertEqual(pencil.end(), [])
        XCTAssertEqual(pencil.begin(Point(x: 900, y: 600)), [])
        XCTAssertEqual(pencil.move(Point(x: 910, y: 602)), [.relative(Point(x: 20, y: 4))])
        XCTAssertEqual(pencil.end(), [])
    }

    func testHeldDragReleasesOnModeSwitchAndRejectsConflictingClicks() {
        var state = InputState()
        XCTAssertEqual(state.apply(.drag(true)), [.down(.left, .zero, clickCount: 1)])
        XCTAssertEqual(state.apply(.strokeEnd), [])
        XCTAssertTrue(state.dragActive)
        XCTAssertEqual(state.apply(.click(.right, 1)), [])
        XCTAssertEqual(state.apply(.mode(.drawing)), [.up(.left, .zero, clickCount: 1)])
        XCTAssertFalse(state.leftHeld)
        XCTAssertEqual(state.release(), [])
    }

    func testStrokeBoundaryReleasePrecedesNewPosition() {
        var state = InputState()
        state.target = Rect(x: 100, y: 200, width: 1000, height: 500)
        _ = state.apply(.mode(.drawing))
        _ = state.apply(.strokeBegin(Point(x: 0.1, y: 0.2)))
        _ = state.apply(.strokeMove(Point(x: 0.2, y: 0.4)))
        XCTAssertEqual(state.apply(.strokeBegin(Point(x: 0.5, y: 0.6))), [
            .up(.left, Point(x: 300, y: 400), clickCount: 1),
            .move(Point(x: 600, y: 500), dragging: false),
            .down(.left, Point(x: 600, y: 500), clickCount: 1)])
        _ = state.apply(.cancel)
        XCTAssertFalse(state.leftHeld)
        XCTAssertEqual(state.apply(.strokeMove(Point(x: 0.9, y: 0.9))), [])
    }

    func testMarginExitAndRotationRequireLift() {
        var pencil = PencilInterpreter()
        pencil.mode = .drawing
        pencil.surface = Rect(x: 0, y: 0, width: 1000, height: 1000)
        pencil.targetAspect = 2
        XCTAssertEqual(pencil.begin(Point(x: 500, y: 500), pressure: 0.5), [.strokeBegin(Point(x: 0.5, y: 0.5))])
        XCTAssertEqual(pencil.move(Point(x: 500, y: 20)), [.strokeEnd])
        XCTAssertEqual(pencil.move(Point(x: 500, y: 500)), [])
        _ = pencil.end()
        XCTAssertEqual(pencil.begin(Point(x: 500, y: 500), pressure: 0.5), [.strokeBegin(Point(x: 0.5, y: 0.5))])
        XCTAssertEqual(pencil.interrupt(), [.cancel])
        XCTAssertEqual(pencil.move(Point(x: 600, y: 500)), [])
        _ = pencil.end()
        XCTAssertFalse(pencil.blocked)
    }

    func testDoubleAndRightClickHaveMatchedDownUpCounts() {
        var state = InputState()
        XCTAssertEqual(state.apply(.click(.left, 1)), [
            .down(.left, .zero, clickCount: 1), .up(.left, .zero, clickCount: 1)])
        XCTAssertEqual(state.apply(.click(.left, 2)), [
            .down(.left, .zero, clickCount: 2), .up(.left, .zero, clickCount: 2)])
        XCTAssertEqual(state.apply(.click(.right, 1)), [.down(.right, .zero, clickCount: 1), .up(.right, .zero, clickCount: 1)])
        XCTAssertFalse(state.leftHeld)
    }
}

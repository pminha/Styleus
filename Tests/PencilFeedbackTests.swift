import XCTest
@testable import StyleusCore

final class PencilFeedbackTests: XCTestCase {
    func testLocalFeedbackDistinguishesFirmTapFromDragAndTracksReleaseHysteresis() {
        var pencil = PencilInterpreter()
        pencil.pressureThreshold = 0.4
        _ = pencil.begin(.zero, pressure: 0.7, at: 1)
        var display = PencilFeedbackPresentation(pencil, enabled: true)
        XCTAssertEqual(display.phase, .pointing) // Firm contact alone is not a drag.
        XCTAssertEqual(display.pressure, 0.7)
        _ = pencil.move(Point(x: 10, y: 0), pressure: 0.7, at: 1.1)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .dragging)
        _ = pencil.move(Point(x: 12, y: 0), pressure: 0.3, at: 1.2)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .dragging)
        _ = pencil.move(Point(x: 14, y: 0), pressure: 0.2, at: 1.3)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .pointing)
        _ = pencil.end(at: 1.4)
        display = PencilFeedbackPresentation(pencil, enabled: true)
        XCTAssertEqual(display.phase, .ready)
        XCTAssertEqual(display.pressure, 0)
        XCTAssertEqual(display.activationPressure, 0.4)
    }

    func testDrawingFeedbackClearsInMarginsAndRequiresFreshContact() {
        var pencil = PencilInterpreter()
        pencil.mode = .drawing
        pencil.surface = Rect(x: 0, y: 0, width: 100, height: 100)
        pencil.targetAspect = 2
        _ = pencil.begin(Point(x: 50, y: 50), pressure: 0.1, at: 1)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .pointing)
        _ = pencil.move(Point(x: 55, y: 50), pressure: 0.6, at: 1.1)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .drawing)
        _ = pencil.move(Point(x: 55, y: 0), pressure: 0.6, at: 1.2)
        var display = PencilFeedbackPresentation(pencil, enabled: true)
        XCTAssertEqual(display.phase, .liftToResume)
        XCTAssertFalse(display.held)
        XCTAssertEqual(display.pressure, 0)
        _ = pencil.move(Point(x: 55, y: 50), pressure: 0.6, at: 1.3)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true), display)
        _ = pencil.end(at: 1.4)
        display = PencilFeedbackPresentation(pencil, enabled: true)
        XCTAssertEqual(display.phase, .ready)
        _ = pencil.begin(Point(x: 50, y: 50), pressure: 0.6, at: 2)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .drawing)
    }

    func testPausedAndInterruptedFeedbackCannotRetainPressureOrHeldState() {
        var pencil = PencilInterpreter()
        _ = pencil.begin(.zero, pressure: 1, at: 1)
        _ = pencil.move(Point(x: 10, y: 0), pressure: 1, at: 1.1)
        XCTAssertTrue(PencilFeedbackPresentation(pencil, enabled: true).held)
        let paused = PencilFeedbackPresentation(pencil, enabled: false)
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.pressure, 0)
        XCTAssertFalse(paused.held)
        _ = pencil.interrupt() // Mode, rotation, settings and session invalidation use this path.
        pencil.mode = .drawing
        let interrupted = PencilFeedbackPresentation(pencil, enabled: true)
        XCTAssertEqual(interrupted.phase, .liftToResume)
        XCTAssertEqual(interrupted.pressure, 0)
        XCTAssertFalse(interrupted.held)
        _ = pencil.end(at: 1.2)
        XCTAssertEqual(PencilFeedbackPresentation(pencil, enabled: true).phase, .ready)
    }
}

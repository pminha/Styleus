#if os(macOS)
import AppKit
import XCTest
@testable import StyleusCore

final class ZoomEventTests: XCTestCase {
    func testDirectEventsDecodeAsNativeFractionalMagnificationWithCorrectPhases() throws {
        XCTAssertTrue(ZoomEventEncoder.available, "This host must support the experimental event layout")
        let cases: [(ZoomPhase, NSEvent.Phase, Double)] = [
            (.began, .began, 0), (.changed, .changed, 0.0037),
            (.changed, .changed, -0.125), (.ended, .ended, 0), (.cancelled, .cancelled, 0)
        ]
        for (phase, nativePhase, delta) in cases {
            let cg = try XCTUnwrap(ZoomEventEncoder.event(ZoomSample(magnification: delta, phase: phase)))
            let ns = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(ns.type, .magnify)
            XCTAssertEqual(ns.phase, nativePhase)
            XCTAssertEqual(ns.magnification, delta, accuracy: 0.000001)
        }
    }

    func testInvalidSamplesNeverConstructInput() {
        for value in [Double.nan, .infinity, -.infinity, -1, 0.501] {
            XCTAssertNil(ZoomEventEncoder.event(ZoomSample(magnification: value, phase: .changed)))
        }
        XCTAssertNil(ZoomEventEncoder.event(ZoomSample(magnification: 0.1, phase: .began)))
        XCTAssertNil(ZoomEventEncoder.event(ZoomSample(magnification: 0.1, phase: .cancelled)))
    }

    func testZoomDoesNotInheritKeyboardModifiersOrMouseButtonSemantics() throws {
        var encoder = MouseEventEncoder()
        let cg = try XCTUnwrap(encoder.event(.zoom(ZoomSample(magnification: 0.01, phase: .changed)),
                                             modifiers: [.maskCommand, .maskControl, .maskAlternate]))
        XCTAssertTrue(cg.flags.intersection(MouseEventEncoder.keyboardModifiers).isEmpty)
        XCTAssertEqual(NSEvent(cgEvent: cg)?.type, .magnify)
    }
}
#endif

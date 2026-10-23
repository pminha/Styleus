import XCTest
import AppKit
@testable import StyleusCore

final class MouseEventTests: XCTestCase {
    private let point = Point(x: 120, y: 240)
    // deviceIndependentFlagsMask also contains other system state bits. Compare
    // the documented keyboard flags, preserving unrelated event flags.
    private let keyboardFlags: NSEvent.ModifierFlags = [
        .capsLock, .shift, .control, .option, .command, .help, .function, .numericPad
    ]

    func testEachModifierReachesAppKitMouseDownDragAndUp() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let flags: [(CGEventFlags, NSEvent.ModifierFlags)] = [
            (.maskCommand, .command), (.maskShift, .shift), (.maskAlternate, .option), (.maskControl, .control)
        ]
        for (cgFlags, nsFlags) in flags {
            var encoder = MouseEventEncoder()
            let effects: [(MouseEffect, NSEvent.EventType)] = [
                (.move(point, dragging: false), .mouseMoved),
                (.down(.left, point, clickCount: 1), .leftMouseDown),
                (.move(Point(x: 150, y: 260), dragging: true), .leftMouseDragged),
                (.up(.left, point, clickCount: 1), .leftMouseUp)
            ]
            for (effect, type) in effects {
                let cg = try XCTUnwrap(encoder.event(effect, source: source, modifiers: cgFlags))
                let event = try XCTUnwrap(NSEvent(cgEvent: cg))
                XCTAssertEqual(event.type, type)
                XCTAssertEqual(event.modifierFlags.intersection(keyboardFlags), nsFlags)
                if type != .mouseMoved { XCTAssertEqual(cg.getIntegerValueField(.mouseEventNumber), 1) }
            }
        }
    }

    func testAllModifierCombinationsSurviveClickPairs() throws {
        let available: [CGEventFlags] = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let native: [NSEvent.ModifierFlags] = [.command, .shift, .option, .control]
        var encoder = MouseEventEncoder()
        var state = InputState()
        for combination in 0..<16 {
            var flags: CGEventFlags = []
            var expected: NSEvent.ModifierFlags = []
            for index in 0..<4 where combination & (1 << index) != 0 {
                flags.formUnion(available[index]); expected.formUnion(native[index])
            }
            for effect in state.apply(.click(.left, 1)) {
                let event = try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(encoder.event(effect, modifiers: flags))))
                XCTAssertEqual(event.modifierFlags.intersection(keyboardFlags), expected)
                XCTAssertEqual(event.clickCount, 1)
            }
            XCTAssertFalse(state.leftHeld)
        }
    }

    func testModifierChangesDuringDragAreNotLatched() throws {
        var encoder = MouseEventEncoder()
        let sequence: [(MouseEffect, CGEventFlags)] = [
            (.down(.left, point, clickCount: 1), []),
            (.move(point, dragging: true), .maskShift),
            (.move(point, dragging: true), [.maskShift, .maskAlternate]),
            (.move(point, dragging: true), []),
            (.up(.left, point, clickCount: 1), [])
        ]
        for (effect, flags) in sequence {
            let event = try XCTUnwrap(encoder.event(effect, modifiers: flags))
            XCTAssertEqual(event.flags.intersection(MouseEventEncoder.keyboardModifiers), flags)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventNumber), 1)
        }
        let next = try XCTUnwrap(encoder.event(.down(.left, point, clickCount: 1), modifiers: []))
        XCTAssertTrue(next.flags.intersection(MouseEventEncoder.keyboardModifiers).isEmpty)
        XCTAssertEqual(next.getIntegerValueField(.mouseEventNumber), 2)
    }

    func testModifiedDoubleAndRightClickPreserveCountsButtonsAndEventNumbers() throws {
        var encoder = MouseEventEncoder()
        var state = InputState()
        for (index, action) in [InputAction.click(.left, 1), .click(.left, 2), .click(.right, 1)].enumerated() {
            let effects = state.apply(action)
            XCTAssertEqual(effects.count, 2)
            for effect in effects {
                let cg = try XCTUnwrap(encoder.event(effect, modifiers: .maskCommand))
                let event = try XCTUnwrap(NSEvent(cgEvent: cg))
                XCTAssertTrue(event.modifierFlags.contains(.command))
                XCTAssertEqual(event.clickCount, index == 1 ? 2 : 1)
                XCTAssertEqual(event.buttonNumber, index == 2 ? 1 : 0)
                XCTAssertEqual(cg.getIntegerValueField(.mouseEventNumber), Int64(index + 1))
            }
        }
    }

    func testCancelledModifiedDragReleasesAndNextContactStartsWithoutModifier() throws {
        for action in [InputAction.cancel, .mode(.drawing)] {
            var state = InputState()
            var encoder = MouseEventEncoder()
            for effect in state.apply(.drag(true)) {
                _ = encoder.event(effect, modifiers: [.maskCommand, .maskAlternate])
            }
            // The physical keys were released before cancellation. The mouse-up
            // must use the current state, not the modifiers from mouse-down.
            let release = try XCTUnwrap(state.apply(action).first)
            let event = try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(encoder.event(release, modifiers: []))))
            XCTAssertEqual(event.type, .leftMouseUp)
            XCTAssertTrue(event.modifierFlags.intersection(keyboardFlags).isEmpty)
            XCTAssertFalse(state.leftHeld)
            for effect in state.apply(.click(.left, 1)) {
                let next = try XCTUnwrap(encoder.event(effect, modifiers: []))
                XCTAssertTrue(next.flags.intersection(MouseEventEncoder.keyboardModifiers).isEmpty)
            }
        }
    }

    func testModifierAdditionPreservesScrollDistancePhasesAndPrecision() throws {
        var encoder = MouseEventEncoder()
        var reference = ScrollEventEncoder()
        for phase in [ScrollPhase.began, .changed, .ended, .momentumBegan, .momentumChanged, .momentumEnded] {
            let sample = ScrollSample(delta: Point(x: -2.5, y: 10.25), phase: phase)
            let cg = try XCTUnwrap(encoder.event(.scroll(sample), modifiers: [.maskShift, .maskAlternate]))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            let expected = try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(reference.event(sample))))
            XCTAssertEqual(event.modifierFlags.intersection(keyboardFlags), [.shift, .option])
            XCTAssertEqual(event.scrollingDeltaX, expected.scrollingDeltaX)
            XCTAssertEqual(event.scrollingDeltaY, expected.scrollingDeltaY)
            XCTAssertEqual(event.phase, expected.phase)
            XCTAssertEqual(event.momentumPhase, expected.momentumPhase)
            XCTAssertTrue(event.hasPreciseScrollingDeltas)
        }
    }

    func testCapsLockAndFunctionFlagsAreCopiedWithoutImportingOtherSessionFlags() throws {
        var encoder = MouseEventEncoder()
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let plain = try XCTUnwrap(encoder.event(.move(point, dragging: false), source: source, modifiers: []))
        let event = try XCTUnwrap(encoder.event(.move(point, dragging: false), source: source,
                                               modifiers: [.maskAlphaShift, .maskSecondaryFn, .maskNonCoalesced]))
        XCTAssertEqual(event.flags.intersection(MouseEventEncoder.keyboardModifiers), [.maskAlphaShift, .maskSecondaryFn])
        XCTAssertEqual(event.flags.subtracting(MouseEventEncoder.keyboardModifiers),
                       plain.flags.subtracting(MouseEventEncoder.keyboardModifiers))
    }
}

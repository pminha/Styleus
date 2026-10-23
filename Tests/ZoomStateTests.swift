import XCTest
@testable import StyleusCore

final class ZoomStateTests: XCTestCase {
    private let began = ZoomSample(phase: .began)
    private let cancelled = ZoomSample(phase: .cancelled)

    func testZoomRequiresBeginAndEndsWithoutResumingFromLateChanges() {
        var state = InputState()
        let change = ZoomSample(magnification: 0.013, phase: .changed)
        XCTAssertEqual(state.apply(.zoom(change)), [])
        XCTAssertEqual(state.apply(.zoom(ZoomSample(phase: .ended))), [])
        XCTAssertEqual(state.apply(.zoom(cancelled)), [])
        XCTAssertFalse(state.zoomActive)

        XCTAssertEqual(state.apply(.zoom(began)), [.zoom(began)])
        XCTAssertTrue(state.zoomActive)
        for value in [0.013, -0.027, 0.5, -0.5] {
            let sample = ZoomSample(magnification: value, phase: .changed)
            XCTAssertEqual(state.apply(.zoom(sample)), [.zoom(sample)])
        }
        let ended = ZoomSample(phase: .ended)
        XCTAssertEqual(state.apply(.zoom(ended)), [.zoom(ended)])
        XCTAssertFalse(state.zoomActive)
        XCTAssertEqual(state.apply(.zoom(change)), [])
        XCTAssertEqual(state.release(), [])
        XCTAssertFalse(state.leftHeld)
    }

    func testRepeatedBeginCancelsPriorGestureBeforeStartingAnother() {
        var state = InputState()
        _ = state.apply(.zoom(began))
        XCTAssertEqual(state.apply(.zoom(began)), [.zoom(cancelled), .zoom(began)])
        XCTAssertTrue(state.zoomActive)
        XCTAssertEqual(state.apply(.zoom(cancelled)), [.zoom(cancelled)])
        XCTAssertFalse(state.zoomActive)
        XCTAssertEqual(state.apply(.zoom(cancelled)), [])
    }

    func testMalformedZoomCancelsWithoutApplyingItsMagnification() {
        var invalid = [Double.nan, .infinity, -.infinity, 0.5001, -0.5001].map {
            ZoomSample(magnification: $0, phase: .changed)
        }
        invalid += [ZoomPhase.began, .ended, .cancelled].map {
            ZoomSample(magnification: 0.1, phase: $0)
        }
        for sample in invalid {
            var state = InputState()
            _ = state.apply(.zoom(began))
            XCTAssertEqual(state.apply(.zoom(sample)), [.zoom(cancelled)])
            XCTAssertFalse(state.zoomActive)
            XCTAssertEqual(state.apply(.zoom(ZoomSample(magnification: 0.02, phase: .changed))), [])
            XCTAssertEqual(state.apply(.zoom(sample)), [])
            XCTAssertFalse(state.leftHeld)
        }
    }

    func testZoomNeverStartsWhileDraggingOrDrawing() {
        for mode in InputMode.allCases {
            var state = InputState()
            state.target = Rect(x: 0, y: 0, width: 100, height: 100)
            _ = state.apply(.mode(mode))
            _ = state.apply(mode == .trackpad ? .drag(true) : .strokeBegin(Point(x: 0.5, y: 0.5)))
            XCTAssertTrue(state.leftHeld)
            XCTAssertEqual(state.apply(.zoom(began)), [])
            XCTAssertEqual(state.apply(.zoom(ZoomSample(magnification: 0.1, phase: .changed))), [])
            XCTAssertFalse(state.zoomActive)
            XCTAssertTrue(state.leftHeld)
            XCTAssertEqual(state.release(), [.up(.left, state.cursor, clickCount: 1)])
            XCTAssertEqual(state.apply(.zoom(ZoomSample(magnification: 0.1, phase: .changed))), [])
            XCTAssertEqual(state.apply(.zoom(began)), [.zoom(began)])
        }
    }

    func testPointerAndModeInputCancelZoomBeforeTheirOwnEffects() {
        let cases: [(InputAction, [MouseEffect])] = [
            (.relative(Point(x: 3, y: 4)), [.move(Point(x: 3, y: 4), dragging: false)]),
            (.click(.left, 1), [.down(.left, .zero, clickCount: 1), .up(.left, .zero, clickCount: 1)]),
            (.drag(true), [.down(.left, .zero, clickCount: 1)]),
            (.mode(.drawing), []),
            (.cancel, []),
            // Even rejected pointer actions end the conflicting zoom gesture.
            (.relative(Point(x: .nan, y: 0)), []),
            (.strokeMove(Point(x: 0.5, y: 0.5)), [])
        ]
        for (action, expected) in cases {
            var state = InputState()
            _ = state.apply(.zoom(began))
            XCTAssertEqual(state.apply(action), [.zoom(cancelled)] + expected)
            XCTAssertFalse(state.zoomActive)
        }
    }

    func testDrawingStrokeCancelsZoomBeforeMovingAndPressing() {
        var state = InputState()
        state.target = Rect(x: 100, y: 200, width: 1000, height: 500)
        _ = state.apply(.mode(.drawing))
        _ = state.apply(.zoom(began))
        let origin = Point(x: 600, y: 450)
        XCTAssertEqual(state.apply(.strokeBegin(Point(x: 0.5, y: 0.5))), [
            .zoom(cancelled), .move(origin, dragging: false), .down(.left, origin, clickCount: 1)
        ])
        XCTAssertFalse(state.zoomActive)
        XCTAssertTrue(state.strokeActive)
        XCTAssertTrue(state.leftHeld)
    }

    func testZoomCancelsContactOrMomentumScrollingBeforeItBegins() {
        for momentum in [false, true] {
            var state = InputState()
            _ = state.apply(.scroll(ScrollSample(delta: Point(x: 0, y: 10), phase: .began)))
            if momentum {
                _ = state.apply(.scroll(ScrollSample(phase: .ended)))
                _ = state.apply(.scroll(ScrollSample(phase: .momentumBegan)))
            }
            let scrollEnd = ScrollSample(phase: momentum ? .momentumEnded : .cancelled)
            XCTAssertEqual(state.apply(.zoom(began)), [.scroll(scrollEnd), .zoom(began)])
            XCTAssertTrue(state.zoomActive)
            XCTAssertEqual(state.release(), [.zoom(cancelled)])
            let stale = ScrollSample(delta: Point(x: 0, y: 4), phase: momentum ? .momentumChanged : .changed)
            XCTAssertEqual(state.apply(.scroll(stale)), [])
        }
    }

    func testScrollingCancelsZoomAndOrphanZoomChangesDoNotInterruptScroll() {
        var state = InputState()
        _ = state.apply(.zoom(began))
        let scroll = ScrollSample(delta: Point(x: 1, y: 2), phase: .began)
        XCTAssertEqual(state.apply(.scroll(scroll)), [.zoom(cancelled), .scroll(scroll)])
        XCTAssertFalse(state.zoomActive)
        XCTAssertEqual(state.apply(.zoom(ZoomSample(magnification: 0.03, phase: .changed))), [])
        let next = ScrollSample(delta: Point(x: 3, y: 4), phase: .changed)
        XCTAssertEqual(state.apply(.scroll(next)), [.scroll(next)])
    }

    func testHeartbeatPreservesZoomButDirectReleaseCancelsExactlyOnce() {
        var state = InputState()
        _ = state.apply(.zoom(began))
        XCTAssertEqual(state.apply(.heartbeat), [])
        XCTAssertTrue(state.zoomActive)
        XCTAssertEqual(state.release(), [.zoom(cancelled)])
        XCTAssertFalse(state.zoomActive)
        XCTAssertEqual(state.release(), [])
        XCTAssertEqual(state.apply(.zoom(ZoomSample(phase: .ended))), [])
    }

    func testExpiredSessionReleaseAndFreshSessionCannotResumeOldZoom() {
        var state = InputState()
        var gate = SessionGate(geometry: 1, now: 0)
        let lease = gate.issueLease(now: 0)
        let begin = InputPacket(session: gate.session, lease: lease, geometry: 1,
                                sequence: 1, action: .zoom(began))
        XCTAssertTrue(gate.accept(begin, now: 0.1))
        XCTAssertEqual(state.apply(begin.action), [.zoom(began)])
        XCTAssertTrue(gate.expired(now: 1.2))
        XCTAssertEqual(state.release(), [.zoom(cancelled)])

        var reconnect = SessionGate(geometry: 1, now: 1.3)
        let newLease = reconnect.issueLease(now: 1.3)
        XCTAssertFalse(reconnect.accept(begin, now: 1.31))
        let orphan = InputPacket(session: reconnect.session, lease: newLease, geometry: 1,
                                 sequence: 1, action: .zoom(ZoomSample(magnification: 0.02, phase: .changed)))
        XCTAssertTrue(reconnect.accept(orphan, now: 1.31))
        XCTAssertEqual(state.apply(orphan.action), [])
        XCTAssertFalse(state.zoomActive)
        XCTAssertFalse(state.leftHeld)
    }
}

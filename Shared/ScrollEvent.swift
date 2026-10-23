#if os(macOS)
import CoreGraphics

/// Builds public continuous-scroll events. Construction never posts input.
struct ScrollEventEncoder {
    private var remainder = Point.zero
    private var linePointRemainder = Point.zero

    mutating func event(_ sample: ScrollSample, source: CGEventSource? = nil) -> CGEvent? {
        guard sample.delta.isFinite, abs(sample.delta.x) <= ScrollSample.maximumDelta, abs(sample.delta.y) <= ScrollSample.maximumDelta else { return nil }
        if sample.phase == .began { remainder = .zero; linePointRemainder = .zero }
        let total = Point(x: sample.delta.x + remainder.x, y: sample.delta.y + remainder.y)
        let pixels = Point(x: total.x.rounded(.towardZero), y: total.y.rounded(.towardZero))
        remainder = Point(x: total.x - pixels.x, y: total.y - pixels.y)
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: 0, wheel2: 0, wheel3: 0) else { return nil }
        let sourceScale = source?.pixelsPerLine ?? 10
        let pixelsPerLine = sourceScale.isFinite && sourceScale > 0 ? sourceScale : 10
        let lines = Point(x: sample.delta.x / pixelsPerLine, y: sample.delta.y / pixelsPerLine)
        let linePoints = Point(x: sample.delta.x + linePointRemainder.x, y: sample.delta.y + linePointRemainder.y)
        let wholeLines = Point(x: (linePoints.x / pixelsPerLine).rounded(.towardZero),
                               y: (linePoints.y / pixelsPerLine).rounded(.towardZero))
        linePointRemainder = Point(x: linePoints.x - wholeLines.x * pixelsPerLine,
                                  y: linePoints.y - wholeLines.y * pixelsPerLine)
        // The constructor forces a nonzero integer wheel step for every nonzero
        // pixel delta, even one point. Set all three representations explicitly.
        // Integer line setters rewrite the other fields, so precise fields go last.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(wholeLines.y))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(wholeLines.x))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: lines.y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: lines.x)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(pixels.y))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(pixels.x))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let phase: Int64
        let momentum: Int64
        switch sample.phase {
        case .began: phase = Int64(CGScrollPhase.began.rawValue); momentum = 0
        case .changed: phase = Int64(CGScrollPhase.changed.rawValue); momentum = 0
        case .ended: phase = Int64(CGScrollPhase.ended.rawValue); momentum = 0
        case .cancelled: phase = Int64(CGScrollPhase.cancelled.rawValue); momentum = 0
        case .momentumBegan: phase = 0; momentum = Int64(CGMomentumScrollPhase.begin.rawValue)
        case .momentumChanged: phase = 0; momentum = Int64(CGMomentumScrollPhase.continuous.rawValue)
        case .momentumEnded: phase = 0; momentum = Int64(CGMomentumScrollPhase.end.rawValue)
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        if sample.phase == .cancelled || sample.phase == .momentumEnded {
            remainder = .zero; linePointRemainder = .zero
        }
        return event
    }
}
#endif

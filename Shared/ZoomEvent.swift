#if os(macOS)
import AppKit
import CoreGraphics

/// Original Swift construction using Core Graphics setters. The gesture type
/// and fields are undocumented Apple SPI; see THIRD_PARTY_NOTICES.md and
/// docs/native-pinch-research.md. No serialized templates or external helper.
struct ZoomEventEncoder {
    static let eventTag: Int64 = 0x5354594C5553
    private static let gestureType = CGEventType(rawValue: 29)!
    private static let gestureKind = CGEventField(rawValue: 110)!
    private static let magnification = CGEventField(rawValue: 113)!
    private static let gesturePhase = CGEventField(rawValue: 132)!

    static let available: Bool = {
        let checks: [(ZoomPhase, NSEvent.Phase, Double)] = [
            (.began, .began, 0), (.changed, .changed, 0.125),
            (.changed, .changed, -0.0625), (.ended, .ended, 0), (.cancelled, .cancelled, 0)
        ]
        return checks.allSatisfy { phase, expectedPhase, delta in
            guard let event = event(ZoomSample(magnification: delta, phase: phase)),
                  let native = NSEvent(cgEvent: event), native.type == .magnify else { return false }
            return native.phase == expectedPhase && abs(native.magnification - delta) < 0.000001
        }
    }()

    static func event(_ sample: ZoomSample, source: CGEventSource? = nil) -> CGEvent? {
        guard sample.isValid, let event = CGEvent(source: source) else { return nil }
        // Setting type first selects the gesture storage used by these fields.
        event.type = gestureType
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        event.setIntegerValueField(gestureKind, value: 8)
        event.setDoubleValueField(magnification, value: sample.magnification)
        let phase: CGGesturePhase
        switch sample.phase {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended: phase = .ended
        case .cancelled: phase = .cancelled
        }
        event.setIntegerValueField(gesturePhase, value: Int64(phase.rawValue))
        return event
    }
}
#endif

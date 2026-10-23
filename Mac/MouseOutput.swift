import AppKit
import ApplicationServices

final class MouseOutput {
    private let source = CGEventSource(stateID: .privateState)
    private var encoder = MouseEventEncoder()
    var permitted: Bool { AXIsProcessTrusted() }
    var location: Point {
        let p = CGEvent(source: nil)?.location ?? .zero
        return Point(x: p.x, y: p.y)
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @discardableResult
    func post(_ effects: [MouseEffect]) -> Point? {
        guard !effects.isEmpty else { return nil }
        var postedLocation: Point?
        // One live snapshot per action keeps an instantaneous click's down/up
        // consistent. Each later drag/move/release action reads the keyboard anew.
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
        for effect in effects {
            let releasing: Bool
            switch effect {
            case .up: releasing = true
            case .scroll(let sample):
                releasing = sample.phase == .ended || sample.phase == .cancelled || sample.phase == .momentumEnded
            default: releasing = false
            }
            // Attempt releases even if Accessibility has just been revoked.
            guard permitted || releasing,
                  let event = encoder.event(effect, source: source, modifiers: modifiers) else { continue }
            if case .scroll(let sample) = effect {
                ScrollDiagnostics.shared.willPost(sample, event: event)
                // Already scaled, phase-aware samples must bypass HID device
                // filters, retaining the physically verified scroll delivery.
                event.post(tap: .cgSessionEventTap)
            } else {
                event.post(tap: .cghidEventTap)
                let point = event.location
                postedLocation = Point(x: point.x, y: point.y)
            }
        }
        return postedLocation
    }
}

struct DisplayChoice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let bounds: Rect
    static func current() -> [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let frame = CGDisplayBounds(id)
            return DisplayChoice(id: id, name: screen.localizedName,
                                 bounds: Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
        }
    }
}

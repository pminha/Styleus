import AppKit
import ApplicationServices
import Combine

/// An explicitly invoked receiver experiment, separate from the basic iPad input path.
/// Public event fields are candidates for compatibility, not a registered tablet driver.
final class PressureProbe: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "Not tested in Notability"
    private let source = CGEventSource(stateID: .privateState)
    private var timer: Timer?
    private var region = Rect(x: 0, y: 0, width: 1, height: 1)
    private var beganAt: TimeInterval = 0
    private var stroke = 0
    private var sample = 0
    private var held = false
    private var proximity = false
    private var last = Point.zero

    func start(region: Rect) {
        cancel()
        guard AXIsProcessTrusted() else { status = "Approve Styleus in Accessibility first."; return }
        guard region.isValid, region.width >= 200, region.height >= 150 else {
            status = "Select a custom region at least 200 × 150 points inside a disposable note."; return
        }
        guard let notability = NSRunningApplication.runningApplications(withBundleIdentifier: "com.gingerlabs.Notability").first else {
            status = "Open a disposable blank Notability note first."; return
        }
        self.region = region; beganAt = ProcessInfo.processInfo.systemUptime + 2
        stroke = 0; sample = 0; running = true
        status = "Starting in 2 seconds. Two test strokes will be added to the selected region."
        notability.activate(options: [])
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    func cancel() {
        if held { post(type: .leftMouseUp, pressure: 0, tilt: 0); held = false }
        if proximity { sendProximity(enter: false) }
        timer?.invalidate(); timer = nil
        if running { status = "Experiment stopped; held input released." }
        running = false
    }

    private func tick() {
        guard running else { return }
        guard AXIsProcessTrusted(), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.gingerlabs.Notability" else {
            cancel(); status = "Stopped because Notability lost focus or permission changed."; return
        }
        guard ProcessInfo.processInfo.systemUptime >= beganAt else { return }
        guard stroke < 2 else {
            cancel()
            status = "Test events sent. Inspect the note: first stroke is constant pressure; second varies pressure and tilt. Delivery is NOT proof that Notability used them."
            return
        }
        let fraction = Double(sample) / 60
        last = Point(x: region.x + region.width * (0.2 + 0.6 * fraction),
                     y: region.y + region.height * (stroke == 0 ? 0.35 : 0.65))
        let pressure = stroke == 0 ? 0.5 : 0.05 + 0.95 * (1 - abs(2 * fraction - 1))
        let tilt = stroke == 0 ? 0 : 0.7 * sin(fraction * .pi)
        if sample == 0 {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: CGPoint(x: last.x, y: last.y), mouseButton: .left)?.post(tap: .cghidEventTap)
            if !proximity { sendProximity(enter: true) }
            post(type: .leftMouseDown, pressure: pressure, tilt: tilt); held = true
        } else {
            post(type: .leftMouseDragged, pressure: pressure, tilt: tilt)
        }
        if sample == 60 {
            post(type: .leftMouseUp, pressure: 0, tilt: 0); held = false
            sample = 0; stroke += 1; beganAt = ProcessInfo.processInfo.systemUptime + 0.3
        } else { sample += 1 }
    }

    private func post(type: CGEventType, pressure: Double, tilt: Double) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                   mouseCursorPosition: CGPoint(x: last.x, y: last.y), mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.mouseEventNumber, value: Int64(100 + stroke))
        event.setIntegerValueField(.mouseEventSubtype, value: 1) // Documented tablet-point subtype.
        event.setIntegerValueField(.tabletEventDeviceID, value: 7)
        event.setIntegerValueField(.tabletEventPointButtons, value: type == .leftMouseUp ? 0 : 1)
        event.setIntegerValueField(.tabletEventPointX, value: Int64((last.x - region.x) / region.width * 65535))
        event.setIntegerValueField(.tabletEventPointY, value: Int64((last.y - region.y) / region.height * 65535))
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        event.setDoubleValueField(.tabletEventTiltX, value: tilt)
        event.setDoubleValueField(.tabletEventTiltY, value: 0)
        event.post(tap: .cghidEventTap)
    }

    private func sendProximity(enter: Bool) {
        let event = CGEvent(source: source)
        event?.type = .tabletProximity
        event?.setIntegerValueField(.tabletProximityEventDeviceID, value: 7)
        event?.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 7)
        event?.setIntegerValueField(.tabletProximityEventPointerType, value: 1) // Pen.
        event?.setIntegerValueField(.tabletProximityEventEnterProximity, value: enter ? 1 : 0)
        event?.post(tap: .cghidEventTap)
        proximity = enter
    }
}

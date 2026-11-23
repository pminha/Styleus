import SwiftUI
import UIKit

struct InputSurface: UIViewRepresentable {
    var mode: InputMode
    var sensitivity: Double
    var pressureThreshold: Double
    var reverseVerticalScroll: Bool
    var reverseHorizontalScroll: Bool
    var scrollSensitivity: Double
    var pinchZoomEnabled: Bool
    var fingerTrackpadEnabled: Bool
    var targetAspect: Double
    var revision: UInt64
    var enabled: Bool
    var feedback: PencilFeedbackRelay
    var action: (InputAction) -> Void
    var pencilStatus: (PencilStatus) -> Void

    func makeUIView(context: Context) -> PencilInputView { PencilInputView() }
    func updateUIView(_ view: PencilInputView, context: Context) {
        view.onAction = action
        view.onStatus = pencilStatus
        view.feedback = feedback
        view.configure(mode: mode, sensitivity: sensitivity, pressureThreshold: pressureThreshold,
                       reverseVerticalScroll: reverseVerticalScroll, reverseHorizontalScroll: reverseHorizontalScroll,
                       scrollSensitivity: scrollSensitivity, pinchZoomEnabled: pinchZoomEnabled,
                       fingerTrackpadEnabled: fingerTrackpadEnabled,
                       aspect: targetAspect, revision: revision, enabled: enabled)
    }
    static func dismantleUIView(_ uiView: PencilInputView, coordinator: ()) { uiView.shutdown() }
}

private final class ScrollFrameTarget: NSObject {
    weak var view: PencilInputView?
    @objc func tick(_ link: CADisplayLink) { view?.scrollFrame() }
}

final class PencilInputView: UIView {
    var onAction: ((InputAction) -> Void)?
    var onStatus: ((PencilStatus) -> Void)?
    weak var feedback: PencilFeedbackRelay? {
        didSet {
            if feedback !== oldValue { updateFeedback() }
        }
    }
    private var interpreter = PencilInterpreter()
    private var finger = FingerTrackpad<ObjectIdentifier>()
    private var fingerTrackpadEnabled = false
    private var pendingFingerHold: DispatchWorkItem?
    private var scroll = TwoFingerGestureInterpreter<ObjectIdentifier>()
    private var motion = ScrollMotion()
    private var displayLink: CADisplayLink?
    private var directTouches: [ObjectIdentifier: Point] = [:]
    private var enabled = false
    private var revision: UInt64 = 0
    private var activePencil: ObjectIdentifier?
    private let pencilDot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    private var feedbackPhase = PencilFeedbackPresentation.Phase.paused

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        pencilDot.isUserInteractionEnabled = false
        pencilDot.isHidden = true
        pencilDot.backgroundColor = .systemBlue
        pencilDot.alpha = 0.6
        pencilDot.layer.cornerRadius = 5
        addSubview(pencilDot)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: PencilInputView, _) in
            view.setNeedsDisplay()
        }
        accessibilityLabel = "Pencil and two-finger scroll area"
        accessibilityHint = "Slide two fingers to scroll. Trackpad: tap the Pencil to click, tap twice to double-click, hold then lift to right-click, press firmly while moving to drag. Drawing: press to draw."
        let target = ScrollFrameTarget()
        target.view = self
        let link = CADisplayLink(target: target, selector: #selector(ScrollFrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate() }

    override var canBecomeFirstResponder: Bool { enabled && fingerTrackpadEnabled }
    // Keep iPadOS text-editing gestures off the trackpad surface.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration {
        fingerTrackpadEnabled ? .none : super.editingInteractionConfiguration
    }

    func shutdown() { interrupt(); displayLink?.invalidate(); displayLink = nil }

    func configure(mode: InputMode, sensitivity: Double, pressureThreshold: Double,
                   reverseVerticalScroll: Bool, reverseHorizontalScroll: Bool, scrollSensitivity: Double,
                   pinchZoomEnabled: Bool, fingerTrackpadEnabled: Bool, aspect: Double,
                   revision: UInt64, enabled: Bool) {
        interpreter.sensitivity = sensitivity
        finger.sensitivity = sensitivity
        let allowFingerPointer = fingerTrackpadEnabled && mode == .trackpad
        guard interpreter.mode != mode || interpreter.targetAspect != aspect ||
            interpreter.pressureThreshold != pressureThreshold || scroll.reverseVertical != reverseVerticalScroll ||
            scroll.reverseHorizontal != reverseHorizontalScroll ||
            scroll.sensitivity != scrollSensitivity ||
            scroll.pinchZoomEnabled != pinchZoomEnabled ||
            self.fingerTrackpadEnabled != allowFingerPointer ||
            self.revision != revision || self.enabled != enabled else { return }
        interrupt(sendCancellation: false)
        interpreter.mode = mode
        interpreter.pressureThreshold = pressureThreshold; interpreter.targetAspect = aspect
        scroll.reverseVertical = reverseVerticalScroll
        scroll.reverseHorizontal = reverseHorizontalScroll
        scroll.sensitivity = scrollSensitivity
        scroll.pinchZoomEnabled = pinchZoomEnabled
        self.fingerTrackpadEnabled = allowFingerPointer
        if allowFingerPointer {
            accessibilityLabel = "Pencil and finger trackpad"
        } else {
            accessibilityLabel = pinchZoomEnabled ? "Pencil, two-finger scroll, and pinch zoom area" : "Pencil and two-finger scroll area"
        }
        accessibilityHint = (allowFingerPointer ? "Slide one finger to point. Tap one finger to click or two fingers to right-click. Slide three fingers to drag, or double-tap and hold with one finger. " : "") +
            (pinchZoomEnabled ? "Slide two fingers to scroll or pinch to zoom. " : "Slide two fingers to scroll. ") +
            "Trackpad: tap the Pencil to click, tap twice to double-click, hold then lift to right-click, press firmly while moving to drag. Drawing: press to draw."
        self.revision = revision; self.enabled = enabled
        if isFirstResponder && !canBecomeFirstResponder { resignFirstResponder() }
        updateFeedback()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = Rect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        if rect != interpreter.surface { interrupt(); interpreter.surface = rect; setNeedsDisplay() }
    }

    func interrupt(sendCancellation: Bool = true) {
        interruptFinger()
        let actions = interpreter.interrupt()
        let endZoom = scroll.interrupt()
        let endScroll = motion.cancel()
        displayLink?.isPaused = true
        updateFeedback()
        if sendCancellation { emitScroll(endScroll); emitZoom(endZoom); emit(actions) }
        pencilDot.isHidden = true
    }

    private func emit(_ actions: [InputAction]) {
        updateFeedback()
        onStatus?(interpreter.status)
        send(actions)
    }
    private func send(_ actions: [InputAction]) { actions.forEach { onAction?($0) } }

    private func cancelFingerHold() {
        pendingFingerHold?.cancel()
        pendingFingerHold = nil
    }

    private func interruptFinger() {
        cancelFingerHold()
        send(finger.interrupt())
    }

    private func scheduleFingerHold() {
        cancelFingerHold()
        guard let deadline = finger.holdDeadline else { return }
        let hold = DispatchWorkItem { [weak self] in
            guard let self, self.finger.holdDeadline == deadline else { return }
            self.pendingFingerHold = nil
            self.send(self.finger.hold(at: deadline))
        }
        pendingFingerHold = hold
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - CACurrentMediaTime()), execute: hold)
    }
    private func updateFeedback() {
        let presentation = PencilFeedbackPresentation(interpreter, enabled: enabled)
        feedback?.update(presentation)
        if feedbackPhase != presentation.phase {
            feedbackPhase = presentation.phase
            pencilDot.backgroundColor = presentation.held ? .systemOrange : .systemBlue
            setNeedsDisplay()
        }
    }
    private func positionDot(for touch: UITouch) {
        UIView.performWithoutAnimation {
            pencilDot.center = touch.preciseLocation(in: self)
            pencilDot.isHidden = false
        }
    }
    private func emitScroll(_ samples: [ScrollSample]) { emit(samples.map(InputAction.scroll)) }
    private func emitZoom(_ samples: [ZoomSample]) { emit(samples.map(InputAction.zoom)) }
    fileprivate func scrollFrame() {
        if enabled { emitScroll(motion.tick(at: CACurrentMediaTime())) }
        else { _ = motion.cancel() }
        displayLink?.isPaused = !motion.needsFrames
    }
    private func point(_ touch: UITouch) -> Point {
        let p = touch.preciseLocation(in: self)
        return Point(x: p.x, y: p.y)
    }
    private func pressure(_ touch: UITouch) -> Double {
        guard touch.maximumPossibleForce > 0, touch.force.isFinite else { return 0 }
        return Double(touch.force / touch.maximumPossibleForce)
    }

    @discardableResult
    private func updateDirectTouches(_ touches: Set<UITouch>, removing: Bool = false) -> Bool {
        var changed = false
        for touch in touches where touch.type == .direct {
            let id = ObjectIdentifier(touch)
            if removing { directTouches.removeValue(forKey: id) }
            else if touch.phase == .began || directTouches[id] != nil {
                let position = point(touch)
                if directTouches[id] != position {
                    directTouches[id] = position
                    changed = true
                }
            }
        }
        return changed
    }

    private func updateScroll(at now: TimeInterval) {
        let wasActive = scroll.active
        let update = scroll.update(directTouches, at: now, pencilDown: activePencil != nil)
        guard enabled else { _ = scroll.interrupt(); _ = motion.cancel(); displayLink?.isPaused = true; return }
        if (!wasActive && scroll.active) || update.zoomSamples.contains(where: { $0.phase == .began }) {
            // Once navigation wins, lifting must not click and a third finger
            // must not convert the same gesture into a drag.
            interruptFinger()
            emit(interpreter.interrupt())
        }
        update.scrollDeltas.forEach { motion.move($0, at: now) }
        if activePencil != nil || directTouches.count > 2 || scroll.zoomActive || !update.zoomSamples.isEmpty {
            emitScroll(motion.cancel())
        } else if wasActive && !scroll.active {
            emitScroll(motion.end(at: now, allFingersUp: directTouches.isEmpty))
        } else if directTouches.isEmpty {
            emitScroll(motion.liftRemainingFingers(at: now))
        }
        emitZoom(update.zoomSamples)
        displayLink?.isPaused = !motion.needsFrames
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let stopped = motion.cancel()
        emitScroll(stopped)
        let onEmptySurface = directTouches.isEmpty
        updateDirectTouches(touches)
        if activePencil == nil, let touch = touches.first(where: { $0.type == .pencil }) {
            // End native magnification before Pencil begin can position or press
            // a mouse button. Existing fingers remain blocked until they lift.
            interruptFinger()
            emitZoom(scroll.interrupt())
            activePencil = ObjectIdentifier(touch)
            if enabled {
                emit(interpreter.begin(point(touch), pressure: pressure(touch), at: touch.timestamp))
                positionDot(for: touch)
            }
        } else if enabled, fingerTrackpadEnabled, activePencil == nil,
                  let touch = touches.first(where: { $0.type == .direct }) {
            if onEmptySurface && !isFirstResponder { becomeFirstResponder() }
            if stopped.contains(where: { $0.phase == .momentumEnded }) {
                // A touch that brakes a flick must not also click on lift.
                interruptFinger()
            } else {
                send(finger.begin(directTouches, at: event?.timestamp ?? touch.timestamp, onEmptySurface: onEmptySurface))
                interpreter.discardPendingTap()
                scheduleFingerHold()
            }
        }
        updateScroll(at: event?.timestamp ?? CACurrentMediaTime())
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = event?.timestamp ?? CACurrentMediaTime()
        updateDirectTouches(touches)
        if enabled, let touch = touches.first(where: { ObjectIdentifier($0) == activePencil }) {
            // Never replay predicted or late corrected samples into another app's committed input.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                emit(interpreter.move(point(sample), pressure: pressure(sample), at: sample.timestamp))
            }
            positionDot(for: touch)
        } else if let id = finger.activeTouch, let touch = touches.first(where: { ObjectIdentifier($0) == id }) {
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                send(finger.move(to: point(sample), at: sample.timestamp))
            }
        } else if enabled, fingerTrackpadEnabled, activePencil == nil {
            send(finger.moveGroup(directTouches, at: now))
        }
        updateScroll(at: now)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = event?.timestamp ?? touches.first?.timestamp ?? CACurrentMediaTime()
        let fingerLift = enabled && fingerTrackpadEnabled && activePencil == nil && touches.contains { $0.type == .direct }
        // UIKit can deliver the final travel on lift. Let scroll or pinch claim
        // that movement before deciding whether these two touches were a tap.
        if fingerLift, updateDirectTouches(touches), directTouches.count == 2 { updateScroll(at: now) }
        let finalPositions = directTouches
        updateDirectTouches(touches, removing: true)
        if let touch = touches.first(where: { ObjectIdentifier($0) == activePencil }) {
            if enabled { emit(interpreter.move(point(touch), pressure: pressure(touch), at: touch.timestamp)) }
            emit(interpreter.end(at: touch.timestamp))
            activePencil = nil; pencilDot.isHidden = true
        } else if fingerLift {
            cancelFingerHold()
            send(finger.end(finalPositions, remaining: directTouches.count, at: now))
        }
        updateScroll(at: now)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.contains(where: { $0.type == .direct }) { interruptFinger() }
        emitScroll(motion.cancel())
        emitZoom(scroll.interrupt())
        updateDirectTouches(touches, removing: true)
        if let touch = touches.first(where: { ObjectIdentifier($0) == activePencil }) {
            interrupt()
            activePencil = nil; _ = interpreter.end(at: touch.timestamp)
            updateFeedback()
        }
        updateScroll(at: event?.timestamp ?? CACurrentMediaTime())
    }

    override func draw(_ rect: CGRect) {
        UIColor.systemGray5.setFill(); UIBezierPath(rect: bounds).fill()
        let area: CGRect
        if interpreter.mode == .drawing, let fitted = interpreter.activeArea {
            area = CGRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height)
        } else { area = bounds.insetBy(dx: 1, dy: 1) }
        UIColor.secondarySystemGroupedBackground.setFill(); UIBezierPath(rect: area).fill()
        if interpreter.mode == .drawing {
            (enabled ? UIColor.systemBlue : UIColor.systemGray).setStroke()
            let border = UIBezierPath(rect: area.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
        }
        let feedback = PencilFeedbackPresentation(interpreter, enabled: enabled)
        let statusColor: UIColor = feedback.held ? .systemOrange : .secondaryLabel
        statusColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: area.minX + 18, y: area.minY + 23, width: 6, height: 6)).fill()
        (feedback.title as NSString).draw(in: CGRect(x: area.minX + 32, y: area.minY + 16,
                                                    width: max(0, area.width - 48), height: 24),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium),
                                                         .foregroundColor: statusColor])
        let fingerHint = scroll.pinchZoomEnabled ? "Slide two fingers to scroll · pinch to zoom" : "Slide two fingers to scroll"
        let text: String
        if !enabled {
            text = "Input paused\nCheck connection and Mac Accessibility approval"
        } else if interpreter.mode == .drawing {
            text = "Light Pencil touch positions the pointer\nPress to draw · ease pressure or lift to end\n\(fingerHint)"
        } else if fingerTrackpadEnabled {
            text = "Slide one finger to point · tap to click\nTap two fingers to right-click · slide three to drag\n\(fingerHint)"
        } else {
            text = "Pencil: tap to click · tap twice to double-click\nHold, then lift to right-click · press while moving to drag\n\(fingerHint)"
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (text as NSString).draw(in: CGRect(x: area.minX + 16, y: area.midY - 40, width: max(0, area.width - 32), height: 100),
                               withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .medium),
                                                .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: style])
    }
}

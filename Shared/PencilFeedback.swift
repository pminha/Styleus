import Foundation

/// Local display state from the same interpreter that produces Pencil actions.
/// It does not wait for a Mac reply or claim that a receiving app applied an action.
struct PencilFeedbackPresentation: Equatable {
    enum Phase { case paused, ready, pointing, dragging, drawing, liftToResume }
    let phase: Phase
    let mode: InputMode
    let pressure: Double
    let activationPressure: Double

    init(_ pencil: PencilInterpreter, enabled: Bool) {
        mode = pencil.mode
        activationPressure = pencil.activationPressure
        pressure = enabled ? pencil.status.pressure : 0
        if !enabled { phase = .paused }
        else if pencil.blocked { phase = .liftToResume }
        else if !pencil.status.contact { phase = .ready }
        else if pencil.active { phase = pencil.mode == .trackpad ? .dragging : .drawing }
        else { phase = .pointing }
    }

    var held: Bool { phase == .dragging || phase == .drawing }
    var contact: Bool { held || phase == .pointing }

    var title: String {
        switch phase {
        case .paused: return "Input paused"
        case .ready: return "Pencil ready"
        case .pointing: return "Pointing"
        case .dragging: return "Dragging"
        case .drawing: return "Drawing"
        case .liftToResume: return "Lift to resume"
        }
    }

    var hint: String {
        switch phase {
        case .paused: return "Check connection and Mac approval"
        case .dragging, .drawing: return "Ease pressure or lift to release"
        case .liftToResume: return "Start a fresh Pencil contact"
        default: return mode == .trackpad ? "Press while moving to drag" : "Press to draw"
        }
    }
}

import SwiftUI
import UIKit

/// A single latest value delivered directly to UIKit, without publishing every
/// pressure sample through SwiftUI or sending any extra network messages.
final class PencilFeedbackRelay {
    private(set) var latest = PencilFeedbackPresentation(PencilInterpreter(), enabled: false)
    private weak var view: PencilPressureView?

    func update(_ value: PencilFeedbackPresentation) {
        latest = value
        view?.presentation = value
    }

    func attach(_ view: PencilPressureView) {
        self.view = view
        view.presentation = latest
    }

    func detach(_ view: PencilPressureView) {
        if self.view === view { self.view = nil }
    }
}

struct PencilPressureMeter: UIViewRepresentable {
    let feedback: PencilFeedbackRelay

    func makeUIView(context: Context) -> PencilPressureView {
        let view = PencilPressureView()
        view.feedback = feedback
        feedback.attach(view)
        return view
    }
    func updateUIView(_ view: PencilPressureView, context: Context) { feedback.attach(view) }
    static func dismantleUIView(_ view: PencilPressureView, coordinator: ()) {
        view.feedback?.detach(view)
    }
}

final class PencilPressureView: UIView {
    weak var feedback: PencilFeedbackRelay?
    var presentation = PencilFeedbackPresentation(PencilInterpreter(), enabled: false) {
        didSet {
            guard presentation != oldValue else { return }
            updateAccessibility()
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Pencil pressure"
        updateAccessibility()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PencilPressureView, _) in
            view.setNeedsDisplay()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 28, height: UIView.noIntrinsicMetric)
    }

    private func updateAccessibility() {
        accessibilityValue = "\(presentation.title), \(Int(presentation.pressure * 100)) percent pressure, activation at \(Int(presentation.activationPressure * 100)) percent"
        accessibilityHint = presentation.hint
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 2, bounds.height > 2,
              let context = UIGraphicsGetCurrentContext() else { return }
        let value = presentation
        let color: UIColor = value.held ? .systemOrange : value.contact ? .systemBlue : .systemGray
        // This view occupies its own narrow column outside the input surface.
        // Redrawing the latest sample directly keeps the rail immediate, with
        // no animation, smoothing, or separate update clock.
        let width = min(14, max(1, bounds.width - 8))
        let inset = min(12, max(1, (bounds.height - 2) / 4))
        let bar = CGRect(x: bounds.midX - width / 2, y: bounds.minY + inset,
                         width: width, height: bounds.height - inset * 2)
        let rail = UIBezierPath(roundedRect: bar, cornerRadius: min(width, bar.height) / 2)
        UIColor.systemGray4.withAlphaComponent(0.55).setFill(); rail.fill()
        if value.contact {
            color.withAlphaComponent(value.held ? 0.22 : 0.08).setFill(); rail.fill()
        }
        context.saveGState()
        rail.addClip()
        color.setFill()
        let fillHeight = bar.height * min(1, max(0, value.pressure))
        context.fill(CGRect(x: bar.minX, y: bar.maxY - fillHeight,
                            width: bar.width, height: fillHeight))
        context.restoreGState()
        (value.contact ? color : UIColor.systemGray3).setStroke()
        rail.lineWidth = value.held ? 2 : 1
        rail.stroke()

        // Pressure rises from the bottom; the fixed cross-mark shows when
        // pressure will activate a drag or stroke without a numeric readout.
        let thresholdY = bar.maxY - bar.height * min(1, max(0, value.activationPressure))
        let marker = UIBezierPath(roundedRect: CGRect(x: max(bounds.minX + 1, bar.minX - 3),
                                                    y: thresholdY - 1,
                                                    width: min(bounds.width - 2, bar.width + 6),
                                                    height: 2), cornerRadius: 1)
        UIColor.label.withAlphaComponent(value.phase == .paused ? 0.25 : 0.7).setFill(); marker.fill()
    }
}

import AppKit
import SwiftUI

/// The activity arc as a Core Animation layer: its turn and its pulse run on
/// the window server, so the app does no work per frame — whatever the
/// notch around it is doing, scaled at rest included.
///
/// Drawn by SwiftUI the arc cost a steady share of a core: each frame of
/// its rotation had the panel re-evaluated and, at rest, the shrunken
/// notch rasterised again. A layer animation is composited by the system
/// and costs the process nothing once it is set.
struct ActivityArcLayer: NSViewRepresentable {
    enum Mode: Equatable {
        /// A short arc turning, one turn per `period`.
        case spin
        /// A full ring breathing, one breath per `period`.
        case pulse
    }

    var mode: Mode
    var color: Color
    var diameter: CGFloat
    var lineWidth: CGFloat
    var period: Double
    /// Drawn once and left: motion reduced.
    var still: Bool = false

    /// How much of the circle the moving arc covers.
    static let arcFraction: CGFloat = 0.25

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.configure(mode: mode, color: NSColor(color), diameter: diameter,
                       lineWidth: lineWidth, period: period, still: still)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArcView, context: Context) -> CGSize? {
        CGSize(width: diameter, height: diameter)
    }

    final class ArcView: NSView {
        private let shape = CAShapeLayer()
        private var current: (mode: Mode, period: Double, still: Bool, diameter: CGFloat)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(shape)
            shape.fillColor = nil
            shape.lineCap = .round
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            shape.frame = bounds
            drawPath()
        }

        private func drawPath() {
            guard let current else { return }
            let radius = (current.diameter - shape.lineWidth) / 2
            let centre = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = CGMutablePath()
            switch current.mode {
            case .spin:
                // From twelve o'clock, clockwise — AppKit's y grows upward,
                // so "clockwise on screen" is a negative sweep here.
                path.addArc(center: centre, radius: radius, startAngle: .pi / 2,
                            endAngle: .pi / 2 - 2 * .pi * ActivityArcLayer.arcFraction, clockwise: true)
            case .pulse:
                path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                           width: radius * 2, height: radius * 2))
            }
            shape.path = path
        }

        func configure(mode: Mode, color: NSColor, diameter: CGFloat,
                       lineWidth: CGFloat, period: Double, still: Bool) {
            shape.strokeColor = color.cgColor
            shape.lineWidth = lineWidth
            let next = (mode: mode, period: period, still: still, diameter: diameter)
            guard current.map({ $0 != next }) ?? true else { return }
            current = next
            drawPath()
            animate()
        }

        /// One animation, replaced only when the mode or the pace changes:
        /// the layer keeps turning on its own in between, which is the
        /// point of it.
        private func animate() {
            shape.removeAllAnimations()
            guard let current, !current.still else {
                shape.transform = CATransform3DIdentity
                shape.opacity = 1
                return
            }
            switch current.mode {
            case .spin:
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0
                // Clockwise on screen, in AppKit's upward y.
                turn.toValue = -2 * Double.pi
                turn.duration = current.period
                turn.repeatCount = .infinity
                turn.isRemovedOnCompletion = false
                shape.add(turn, forKey: "turn")
            case .pulse:
                let breath = CABasicAnimation(keyPath: "opacity")
                breath.fromValue = 1
                breath.toValue = 0.3
                breath.duration = current.period / 2
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shape.add(breath, forKey: "breath")
            }
        }
    }
}

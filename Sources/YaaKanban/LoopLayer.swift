import AppKit
import SwiftUI

/// An endless status animation run by Core Animation. SwiftUI's own repeating animations
/// (`keyframeAnimator`, `repeatForever`) recompute the view graph and lay out the whole window on
/// every frame on the main thread; a layer animation runs in the render server and costs the app
/// next to nothing while it plays. Decoration only: it takes no clicks.
struct LoopLayer: View {
    enum Kind: Equatable {
        /// A 70 % arc of `lineWidth` turning clockwise once every 1.1 s, inset by `inset` points.
        case spin(lineWidth: CGFloat, inset: CGFloat)
        /// A disc swelling to 1.45 times its size as it fades out, every 1.6 s.
        case halo
        /// A light up to `length` points long running down the view over 1.4 s, then a 0.3 s pause.
        case light(length: CGFloat)
        /// A rounded rectangle breathing between faint and clear, 0.55 s each way.
        case flash(radius: CGFloat)
    }

    let kind: Kind
    let tint: Color

    var body: some View {
        Representable(kind: kind, tint: tint).allowsHitTesting(false)
    }

    private struct Representable: NSViewRepresentable {
        let kind: Kind
        let tint: Color
        func makeNSView(context: Context) -> LoopLayerView { LoopLayerView() }
        func updateNSView(_ view: LoopLayerView, context: Context) { view.configure(kind, tint: tint) }
    }
}

final class LoopLayerView: NSView {
    private var kind: LoopLayer.Kind?
    private var tint: Color?
    /// The size the running animation was built for; nil when it has to be built again.
    private var builtSize: CGSize?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ kind: LoopLayer.Kind, tint: Color) {
        guard kind != self.kind || tint != self.tint else { return }
        self.kind = kind
        self.tint = tint
        rebuild()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    // A view taken out of its window loses its animations: build them again when it is back.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuild()
    }

    private func rebuild() {
        builtSize = nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let kind, window != nil, bounds.width > 0, bounds.height > 0, builtSize != bounds.size else { return }
        builtSize = bounds.size
        build(kind)
    }

    /// The tint at `alpha`, as the current appearance (light or dark) resolves it.
    private func color(_ alpha: CGFloat) -> CGColor {
        var out = CGColor.clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let c = NSColor(tint ?? .clear).usingColorSpace(.sRGB) ?? .clear
            out = c.withAlphaComponent(c.alphaComponent * alpha).cgColor
        }
        return out
    }

    private func build(_ kind: LoopLayer.Kind) {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.sublayers = nil
        root.masksToBounds = false
        root.cornerRadius = 0
        let b = bounds
        switch kind {
        case let .spin(lineWidth, inset):
            let ring = CAShapeLayer()
            ring.frame = b
            ring.path = CGPath(ellipseIn: b.insetBy(dx: inset, dy: inset), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = color(1)
            ring.lineWidth = lineWidth
            ring.lineCap = .round
            ring.strokeEnd = 0.7
            root.addSublayer(ring)
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            // The view is flipped: a positive angle turns clockwise on screen, as SwiftUI's did.
            a.fromValue = 0
            a.toValue = 2 * Double.pi
            a.duration = 1.1
            a.repeatCount = .infinity
            ring.add(a, forKey: "loop")
        case .halo:
            let disc = CAShapeLayer()
            disc.frame = b
            disc.path = CGPath(ellipseIn: CGRect(origin: .zero, size: b.size), transform: nil)
            disc.fillColor = color(0.25)
            root.addSublayer(disc)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 1.45
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [scale, fade]
            g.duration = 1.6
            g.repeatCount = .infinity
            disc.add(g, forKey: "loop")
        case let .light(length):
            let run = min(length, b.height * 0.45)
            root.masksToBounds = true
            root.cornerRadius = b.width / 2
            let light = CAGradientLayer()
            light.bounds = CGRect(x: 0, y: 0, width: b.width, height: run)
            // Opaque through its middle, fading only at the ends.
            light.colors = [color(0), color(1), color(1), color(0)]
            light.locations = [0, 0.4, 0.8, 1]
            light.startPoint = CGPoint(x: 0.5, y: 0)
            light.endPoint = CGPoint(x: 0.5, y: 1)
            // At rest just past the bottom, where the pause holds it.
            light.position = CGPoint(x: b.midX, y: b.height + run / 2)
            root.addSublayer(light)
            let move = CABasicAnimation(keyPath: "position.y")
            move.fromValue = -run / 2
            move.toValue = b.height + run / 2
            move.duration = 1.4
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let g = CAAnimationGroup()
            g.animations = [move]
            g.duration = 1.7
            g.repeatCount = .infinity
            light.add(g, forKey: "loop")
        case let .flash(radius):
            let wash = CALayer()
            wash.frame = b
            wash.cornerRadius = min(radius, b.width / 2, b.height / 2)
            wash.cornerCurve = .continuous
            wash.backgroundColor = color(0.04)
            root.addSublayer(wash)
            let a = CABasicAnimation(keyPath: "backgroundColor")
            a.fromValue = color(0.04)
            a.toValue = color(0.34)
            a.duration = 0.55
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wash.add(a, forKey: "loop")
        }
    }
}

import AppKit
import SwiftUI

/// Borderless panel that can still take clicks without activating the app.
private final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Always-on-top rounded panel on every Space: no title bar, sized to its content, draggable,
/// snapping to screen edges.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: AppModel
    private let room = PanelRoom()
    /// Gap kept to the screen's usable area, matching where snapping puts the panel.
    static let margin: CGFloat = 8
    static let snapDistance: CGFloat = 24
    static let radius: CGFloat = 16
    static let width: CGFloat = 340

    init(model: AppModel) {
        self.model = model
        panel = BoardPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 120))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: Self.radius)
        // SwiftUI reports the content's natural height and the window follows it; the content is
        // top-aligned in the window, so a resize in flight never moves its top edge.
        let host = NSHostingView(rootView: FloatingPanelView(
            onHide: { [weak self] in self?.setVisible(false) },
            onHeight: { [weak self] h in
                // Outside the layout pass that reported it; top alignment hides the one-frame lag.
                DispatchQueue.main.async { self?.fit(height: h) }
            },
            room: room)
            .environment(model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = blur.bounds
        blur.addSubview(host)
        // Hairline edge so the panel reads against any wallpaper.
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.radius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        panel.contentView = blur

        if !panel.setFrameUsingName("YaaFloatingPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - Self.width - 16, y: f.maxY - 136))
        }
        panel.setFrameAutosaveName("YaaFloatingPanel")
        updateRoom()
        // Dock, resolution or display arrangement changed.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRoom() }
        }
        applyOpacity()
    }

    var isVisible: Bool { panel.isVisible }

    func applyOpacity() { panel.alphaValue = model.settings.panelOpacity }

    func setVisible(_ on: Bool) {
        if on {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = model.settings.panelOpacity }
        } else {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                                 completionHandler: { [panel] in Task { @MainActor in panel.orderOut(nil) } })
        }
        model.settings.showPanel = on
    }

    func toggle() { setVisible(!(panel.isVisible && panel.alphaValue > 0)) }

    /// Resizes to the content, keeping the edge it is snapped to (top unless at the bottom) in
    /// place, and always inside the screen's usable area.
    private func fit(height: CGFloat) {
        let h = ceil(height)
        guard h > 0, abs(panel.frame.height - h) >= 1 else { return }
        var f = panel.frame
        let pinBottom = panel.screen.map { f.minY - $0.visibleFrame.minY < Self.snapDistance } ?? false
        if !pinBottom { f.origin.y = f.maxY - h }
        f.size = NSSize(width: Self.width, height: h)
        if let v = usable { f.origin.y = min(max(f.minY, v.minY), max(v.minY, v.maxY - f.height)) }
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    /// The screen's usable area less the snapping margin.
    private var usable: NSRect? {
        panel.screen.map { $0.visibleFrame.insetBy(dx: Self.margin, dy: Self.margin) }
    }

    private func updateRoom() {
        let h = usable?.height ?? .infinity
        if room.height != h { room.height = h }
    }

    func windowDidChangeScreen(_ notification: Notification) { updateRoom() }

    func windowDidMove(_ notification: Notification) {
        updateRoom()
        // Snap once the drag settles.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(snapLater), object: nil)
        perform(#selector(snapLater), with: nil, afterDelay: 0.15)
    }

    @objc private func snapLater() { snap() }

    private func snap() {
        guard let v = usable else { return }
        var f = panel.frame
        let d = Self.snapDistance
        if abs(f.minX - v.minX) < d { f.origin.x = v.minX }
        if abs(f.maxX - v.maxX) < d { f.origin.x = v.maxX - f.width }
        if abs(f.minY - v.minY) < d { f.origin.y = v.minY }
        if abs(f.maxY - v.maxY) < d { f.origin.y = v.maxY - f.height }
        // Dropped partly off the bottom or top: pull it back in.
        f.origin.y = min(max(f.minY, v.minY), max(v.minY, v.maxY - f.height))
        if f != panel.frame { panel.setFrame(f, display: true, animate: true) }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

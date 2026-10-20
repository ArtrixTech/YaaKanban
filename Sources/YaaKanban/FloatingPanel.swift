import AppKit
import SwiftUI

/// Borderless panel that can still take clicks without activating the app.
private final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Reports the pointer entering the panel whether or not the app is active (SwiftUI's hover
/// only tracks while it is).
private final class HoverView: NSVisualEffectView {
    var onEnter: () -> Void = {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // `.inVisibleRect` follows resizes itself; re-adding it would report an entry each time.
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
}

/// Always-on-top rounded panel on every Space: no title bar, sized to its content, draggable,
/// snapping to screen edges. Snapped to the left or right edge it can fold into a sidebar rail.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    /// The visible panel, inside the window.
    private let blur: HoverView
    /// The SwiftUI content, inside `blur`.
    private var host = NSView()
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
        blur = HoverView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 120))
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

        blur.autoresizingMask = [.width, .height]
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: Self.radius)
        // SwiftUI reports the content's natural height and the window follows it; the content is
        // top-aligned in the window, so a resize in flight never moves its top edge.
        let host = NSHostingView(rootView: FloatingPanelView(
            onHide: { [weak self] in self?.setVisible(false) },
            onSize: { [weak self] size in
                // Outside the layout pass that reported it; top alignment hides the one-frame lag.
                DispatchQueue.main.async { self?.fit(size) }
            },
            room: room)
            .environment(model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = blur.bounds
        blur.addSubview(host)
        self.host = host
        blur.onEnter = { [weak self] in self?.pointerEntered() }
        // Hairline edge so the panel reads against any wallpaper.
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.radius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        // The window may be larger than the panel while it slides (see `fit`); the rest is clear,
        // so clicks there go through.
        let root = NSView(frame: blur.frame)
        root.addSubview(blur)
        panel.contentView = root

        if !panel.setFrameUsingName("YaaFloatingPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - Self.width - 16, y: f.maxY - 136))
        }
        panel.setFrameAutosaveName("YaaFloatingPanel")
        updateRoom()
        updateDock()
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

    /// A fold or unfold in flight, in screen coordinates.
    private struct Slide { var from: NSRect; var to: NSRect; var start: CFTimeInterval }
    private var slide: Slide?
    private var link: CADisplayLink?
    /// Last size the content asked for, to settle on after a slide.
    private var lastSize: CGSize?
    static let slideDuration: CFTimeInterval = 0.14

    /// Where the panel is drawn now, in screen coordinates.
    private var shown: NSRect { blur.frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) }

    /// Resizes to the content, keeping the edges it is snapped to (top unless at the bottom, and
    /// the side it is docked to) in place, and always inside the screen's usable area. A change of
    /// width (folding or unfolding) slides the panel edge; height alone follows at once.
    private func fit(_ size: CGSize) {
        lastSize = size
        let w = ceil(size.width), h = ceil(size.height)
        let current = slide?.to ?? panel.frame
        guard w > 0, h > 0, abs(current.height - h) >= 1 || abs(current.width - w) >= 1 else { return }
        var f = current
        let pinBottom = panel.screen.map { f.minY - $0.visibleFrame.minY < Self.snapDistance } ?? false
        if !pinBottom { f.origin.y = f.maxY - h }
        if room.dock == .right { f.origin.x = f.maxX - w }
        f.size = NSSize(width: w, height: h)
        if let v = usable {
            f.origin.y = min(max(f.minY, v.minY), max(v.minY, v.maxY - f.height))
            f.origin.x = min(max(f.minX, v.minX), max(v.minX, v.maxX - f.width))
        }
        if slide == nil && (abs(current.width - w) < 1 || room.resizing) {
            panel.setFrame(f, display: true)
            panel.invalidateShadow()
            return
        }
        // Resizing the window itself leaves its new part blank for a few frames, and the pointer
        // falls through it (hover lost, clicks missed). So the window takes both shapes at once and
        // the panel slides inside it, redrawn every frame.
        let from = shown
        slide = Slide(from: from, to: f, start: CACurrentMediaTime())
        host.autoresizingMask = []
        place(window: from.union(f), panel: from)
        if link == nil {
            let l = blur.displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    @objc private func step() {
        guard let s = slide else { return }
        let t = min(1, (CACurrentMediaTime() - s.start) / Self.slideDuration)
        let e = 1 - pow(1 - t, 5)  // ease out: most of the way at once, then settling
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let r = NSRect(x: mix(s.from.minX, s.to.minX), y: mix(s.from.minY, s.to.minY),
                       width: mix(s.from.width, s.to.width), height: mix(s.from.height, s.to.height))
        blur.frame = r.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
        holdContent()
        panel.invalidateShadow()
        guard t >= 1 else { return }
        link?.invalidate()
        link = nil
        place(window: s.to, panel: s.to)
        slide = nil
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        // The content may have asked for another size mid-slide.
        if let l = lastSize { fit(l) }
    }

    /// Mid-slide the content keeps its final size and place on screen, so it never re-lays out
    /// (which would drop hover) and the panel's moving edge just uncovers or covers it.
    private func holdContent() {
        guard let s = slide else { return }
        let origin = shown.origin
        host.frame = s.to.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    /// Sets the window frame and the panel within it in one go, both in screen coordinates.
    private func place(window w: NSRect, panel p: NSRect) {
        panel.setFrame(w, display: false)
        blur.frame = p.offsetBy(dx: -w.minX, dy: -w.minY)
        if slide != nil { holdContent() }
        panel.displayIfNeeded()
        panel.invalidateShadow()
    }

    // MARK: Peek: the rail unfolds while the pointer is over it.

    private var peekPending: DispatchWorkItem?
    private var peekTimer: Timer?
    private var outsideSince: Date?
    static let peekDelay: TimeInterval = 0.03
    static let unpeekDelay: TimeInterval = 0.15

    private var folded: Bool { room.dock != nil && !model.settings.sidebarExpanded }

    /// Entering the rail unfolds it after a short dwell, so passing over it does nothing.
    private func pointerEntered() {
        peekPending?.cancel()
        guard folded, !room.peek else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shown.contains(NSEvent.mouseLocation) else { return }
            self.startPeek()
        }
        peekPending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDelay, execute: work)
    }

    private func startPeek() {
        guard folded, !room.peek else { return }
        room.peek = true
        outsideSince = nil
        // Polled rather than hover-tracked: the window changes size under the pointer, and a
        // default-mode timer pauses while a context menu is open.
        peekTimer?.invalidate()
        peekTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPeek() }
        }
    }

    private func checkPeek() {
        guard room.peek, folded else { return endPeek() }
        let inside = shown.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if inside || NSEvent.pressedMouseButtons != 0 { outsideSince = nil; return }
        let since = outsideSince ?? Date()
        outsideSince = since
        if Date().timeIntervalSince(since) >= Self.unpeekDelay { endPeek() }
    }

    private func endPeek() {
        peekTimer?.invalidate()
        peekTimer = nil
        if room.peek { room.peek = false }
    }

    /// Which side the panel sits against, if any. Only changes when a move settles, so the panel
    /// does not fold or unfold under the pointer mid-drag.
    private func updateDock() {
        guard let v = usable else { return }
        let f = panel.frame, d = Self.snapDistance
        let dock: DockEdge? = abs(f.maxX - v.maxX) < d ? .right : abs(f.minX - v.minX) < d ? .left : nil
        if room.dock != dock { room.dock = dock }
        if dock == nil { endPeek() }
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
        guard slide == nil else { return }  // our own slide, not a drag
        // Snap once the drag settles.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(snapLater), object: nil)
        perform(#selector(snapLater), with: nil, afterDelay: 0.15)
    }

    @objc private func snapLater() {
        // Still dragging (paused), or sliding open or shut: wait.
        if NSEvent.pressedMouseButtons & 1 != 0 || slide != nil {
            perform(#selector(snapLater), with: nil, afterDelay: 0.15)
            return
        }
        snap()
        updateDock()
    }

    private func snap() {
        guard let v = usable else { return }
        var f = panel.frame
        let d = Self.snapDistance
        if abs(f.minX - v.minX) < d { f.origin.x = v.minX }
        if abs(f.maxX - v.maxX) < d { f.origin.x = v.maxX - f.width }
        if abs(f.minY - v.minY) < d { f.origin.y = v.minY }
        if abs(f.maxY - v.maxY) < d { f.origin.y = v.maxY - f.height }
        // Dropped partly off an edge: pull it back in (against that edge, so a side docks).
        f.origin.y = min(max(f.minY, v.minY), max(v.minY, v.maxY - f.height))
        f.origin.x = min(max(f.minX, v.minX), max(v.minX, v.maxX - f.width))
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


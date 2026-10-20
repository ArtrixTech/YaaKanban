import AppKit
import SwiftUI

/// Always-on-top panel on every Space, draggable, snapping to screen edges.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: AppModel
    static let snapDistance: CGFloat = 24

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                        styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(width: 260, height: 120)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatingPanelView().environment(model))
        if !panel.setFrameUsingName("YaaFloatingPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 360, y: f.maxY - 300))
        }
        panel.setFrameAutosaveName("YaaFloatingPanel")
        applyOpacity()
    }

    var isVisible: Bool { panel.isVisible }

    func applyOpacity() { panel.alphaValue = model.settings.panelOpacity }

    func setVisible(_ on: Bool) {
        if on { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        model.settings.showPanel = on
    }

    func toggle() { setVisible(!panel.isVisible) }

    func windowWillClose(_ notification: Notification) { model.settings.showPanel = false }

    func windowDidEndLiveResize(_ notification: Notification) { snap() }
    func windowDidMove(_ notification: Notification) {
        // Snap once the drag settles.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(snapLater), object: nil)
        perform(#selector(snapLater), with: nil, afterDelay: 0.15)
    }

    @objc private func snapLater() { snap() }

    private func snap() {
        guard let screen = panel.screen else { return }
        let v = screen.visibleFrame
        var f = panel.frame
        let d = Self.snapDistance
        if abs(f.minX - v.minX) < d { f.origin.x = v.minX }
        if abs(f.maxX - v.maxX) < d { f.origin.x = v.maxX - f.width }
        if abs(f.minY - v.minY) < d { f.origin.y = v.minY }
        if abs(f.maxY - v.maxY) < d { f.origin.y = v.maxY - f.height }
        if f != panel.frame { panel.setFrame(f, display: true, animate: true) }
    }
}

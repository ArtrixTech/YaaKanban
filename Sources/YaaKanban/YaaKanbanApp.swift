import AppKit
import SwiftUI
import YaaCore

@main
struct YaaKanbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(panel: delegate.panel).environment(delegate.model)
        } label: {
            MenuBarLabel().environment(delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("YaaKanban", id: "main") {
            MainWindow().environment(delegate.model)
        }
        .defaultSize(width: 960, height: 620)

        Settings {
            SettingsView(panel: delegate.panel).environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var panel = FloatingPanelController(model: model)
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        if model.settings.showPanel { panel.setVisible(true) }
        hotKey = HotKey { [weak self] in Task { @MainActor in self?.panel.toggle() } }
        model.onSnapshot = { [weak self] dir in self?.snapshot(to: dir) }
    }

    /// Renders each surface offscreen into `dir`.
    private func snapshot(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if model.selection == nil { model.selection = model.activeSessions.first?.id }
        let views: [(String, AnyView, NSSize)] = [
            ("panel", AnyView(FloatingPanelView().environment(model)), NSSize(width: 340, height: 300)),
            ("menu", AnyView(MenuContent(panel: panel).environment(model)), NSSize(width: 380, height: 420)),
            ("main", AnyView(MainWindow().environment(model)), NSSize(width: 1000, height: 640)),
            ("settings", AnyView(SettingsView(panel: panel).environment(model)), NSSize(width: 480, height: 560)),
        ]
        for (name, view, size) in views {
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            // cacheDisplay skips the window background, so paint it in the view itself.
            window.contentView = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                defer { window.orderOut(nil) }
                guard let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

/// Menu-bar icon: tinted by the most urgent state, with a count of sessions needing attention.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: icon(count: model.attentionCount, running: model.sessions.values.contains { $0.status == .running }))
    }

    private func icon(count: Int, running: Bool) -> NSImage {
        let color: NSColor? = model.hasNeedsInput ? .systemRed : (model.hasStuck ? .systemOrange : nil)
        let symbol = NSImage(systemSymbolName: running ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                             accessibilityDescription: "YaaKanban")!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))!
        let text = count > 0 ? "\(count)" as NSString : nil
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                                                    .foregroundColor: color ?? NSColor.black]
        let textSize = text?.size(withAttributes: attrs) ?? .zero
        let size = NSSize(width: symbol.size.width + (text == nil ? 0 : textSize.width + 3), height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let y = (18 - symbol.size.height) / 2
            if let color {
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                color.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(at: NSPoint(x: 0, y: y), from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                symbol.draw(at: NSPoint(x: 0, y: y), from: .zero, operation: .sourceOver, fraction: 1)
            }
            text?.draw(at: NSPoint(x: symbol.size.width + 3, y: (18 - textSize.height) / 2), withAttributes: attrs)
            return true
        }
        // Template (auto light/dark) when nothing is urgent.
        img.isTemplate = color == nil
        return img
    }
}

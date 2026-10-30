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
            MenuBarLabel().modifier(WindowOpener()).environment(delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("YaaKanban", id: "main") {
            MainWindow().environment(delegate.model)
                .onAppear { Dock.show("main") }
                .onDisappear { Dock.hide("main") }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppWindows.open(.settings) }.keyboardShortcut(",")
            }
        }

        Window(String(localized: "Set Up YaaKanban"), id: SetupGuide.id) {
            SetupGuide().environment(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var panel = FloatingPanelController(model: model)
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppLanguage.atLaunch  // pin the language this process loaded before Settings can change it
        model.start()
        model.updater.start()
        if model.settings.showPanel { panel.setVisible(true) }
        hotKey = HotKey { [weak self] in Task { @MainActor in self?.panel.toggle() } }
        model.onSnapshot = { [weak self] dir in self?.snapshot(to: dir) }
        // A timer, not a GCD block: a modal alert run inside a main-queue block stalls every
        // main-actor Task (ingest, permission requests) until it is answered.
        // The setup guide asks about statistics itself; the menu-bar label must exist to open it.
        let guide = model.showSetupAtLaunch
        Timer.scheduledTimer(withTimeInterval: guide ? 1 : 3, repeats: false) { [model] _ in
            MainActor.assumeIsolated { if guide { AppWindows.open(.setup) } else { model.telemetry.askIfNeeded() } }
        }
    }

    /// Renders each surface offscreen into `dir`.
    private func snapshot(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let home = model.selection
        model.selection = model.activeSessions.first?.id ?? home
        let views: [(String, AnyView, NSSize)] = [
            ("panel", AnyView(FloatingPanelView().environment(model)), NSSize(width: model.settings.panelWidth, height: 300)),
            ("rail", AnyView(FloatingPanelView(room: { let r = PanelRoom(dock: .right); r.snapshotFolded = true; return r }()).environment(model)), NSSize(width: Rail.width, height: 600)),
            ("rail-wide", AnyView(FloatingPanelView(room: PanelRoom(dock: .right, peek: true)).environment(model)),
             NSSize(width: model.settings.panelWidth, height: 600)),
            ("menu", AnyView(MenuContent(panel: panel).environment(model)), NSSize(width: 230, height: 230)),
            ("main", AnyView(MainWindow().environment(model)), NSSize(width: 1000, height: 640)),
            ("main-light", AnyView(MainWindow().environment(model)), NSSize(width: 1000, height: 640)),
            ("main-overview", AnyView(MainWindow(page: AppModel.overview).environment(model)), NSSize(width: 1000, height: 760)),
            ("settings", AnyView(MainWindow(page: AppModel.settingsPage).environment(model)), NSSize(width: 1000, height: 760)),
            ("settings-alerts", AnyView(MainWindow(page: AppModel.settingsPage, tab: .alerts).environment(model)), NSSize(width: 1000, height: 900)),
            ("setup", AnyView(SetupGuide(live: false).environment(model)), SetupGuide.size),
            ("setup-finish", AnyView(SetupGuide(step: .finish, live: false).environment(model)), SetupGuide.size),
            ("dashboard", AnyView(DashboardView().environment(model)), NSSize(width: 1000, height: 1500)),
            ("dashboard-wide", AnyView(DashboardView().environment(model)), NSSize(width: 1320, height: 1200)),
            ("dashboard-week", AnyView(DashboardView(period: .week).environment(model)), NSSize(width: 1000, height: 900)),
            ("dashboard-month", AnyView(DashboardView(period: .month).environment(model)), NSSize(width: 1000, height: 900)),
        ]
        for (name, view, size) in views {
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            // "-light" renders in the light appearance whatever the system's.
            if name.hasSuffix("-light") { window.appearance = NSAppearance(named: .aqua) }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.model.selection = home }
    }

    /// The Dock icon (shown while the main window or the setup guide is open) brings the guide
    /// back, else the main window. Clicking a notification sends a reopen too: its jump to the
    /// session must not end under the main window, so a reopen right after one does nothing.
    /// False, or SwiftUI opens the main window itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The click's response can arrive just after the reopen.
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [model] _ in
            MainActor.assumeIsolated {
                guard Date().timeIntervalSince(model.notificationActedAt) > 1.5 else { return }
                AppWindows.open(Dock.holds(SetupGuide.id) ? .setup : .main)
            }
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

/// Menu-bar icon: the logo's three bars in outline, a dot when something is going on (tinted by
/// the most urgent state), and a count of sessions waiting on the user.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: icon(count: model.pendingCount, running: model.runningCount > 0))
    }

    private func icon(count: Int, running: Bool) -> NSImage {
        // Purple: asking you. Orange: stuck. Green: finished, waiting to be reviewed.
        let color: NSColor? = model.hasNeedsInput ? .systemPurple
            : model.hasStuck ? .systemOrange
            : model.reviewCount > 0 ? .systemGreen : nil
        let text = count > 0 ? "\(count)" as NSString : nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let textSize = text?.size(withAttributes: [.font: font]) ?? .zero
        let mark: CGFloat = 16
        let size = NSSize(width: mark + (text == nil ? 0 : textSize.width + 3), height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            // Drawn in labelColor when tinted (no template then), so it still follows the menu bar.
            let ink = NSColor.labelColor
            ink.setFill()
            // The logo's columns on a 16 pt grid: full, two-thirds and one-third height.
            let top: CGFloat = 2.5, full: CGFloat = 13, w: CGFloat = 3.6
            for (i, h) in [full, full * 0.66, full * 0.38].enumerated() {
                let x = 1 + CGFloat(i) * 5.2
                NSBezierPath(roundedRect: NSRect(x: x, y: top, width: w, height: h), xRadius: 1.4, yRadius: 1.4).fill()
            }
            if running || color != nil {
                (color ?? ink).setFill()
                // Under the short column, its bottom on the long one's, as in the logo.
                NSBezierPath(ovalIn: NSRect(x: 1 + 2 * 5.2 + w / 2 - 2.1, y: top + full - 4.2, width: 4.2, height: 4.2)).fill()
            }
            if let text {
                text.draw(at: NSPoint(x: mark + 3, y: (18 - textSize.height) / 2),
                          withAttributes: [.font: font, .foregroundColor: color ?? ink])
            }
            return true
        }
        // Template (auto light/dark) when nothing is tinted.
        img.isTemplate = color == nil
        return img
    }
}

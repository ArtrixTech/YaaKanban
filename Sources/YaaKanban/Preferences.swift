import Foundation
import Observation
import YaaCore

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class Preferences {
    private let d = UserDefaults.standard

    var stuckMinutes: Double { didSet { d.set(stuckMinutes, forKey: "stuckMinutes") } }
    var approvalTimeout: Double { didSet { d.set(approvalTimeout, forKey: "approvalTimeout") } }
    var idleVisibleMinutes: Double { didSet { d.set(idleVisibleMinutes, forKey: "idleVisibleMinutes") } }
    /// A card waiting on the user flashes once it has waited this long unclicked.
    var flashEnabled: Bool { didSet { d.set(flashEnabled, forKey: "flashEnabled") } }
    var flashAfterSeconds: Double { didSet { d.set(flashAfterSeconds, forKey: "flashAfterSeconds") } }
    /// A finished turn left unreviewed flashes once the user has been at the Mac this long without opening it.
    var reviewFlashEnabled: Bool { didSet { d.set(reviewFlashEnabled, forKey: "reviewFlashEnabled") } }
    var reviewFlashMinutes: Double { didSet { d.set(reviewFlashMinutes, forKey: "reviewFlashMinutes") } }
    /// A reviewed turn left alone turns blue from this long after it ended (see `Attention.staleness`).
    var staleTintEnabled: Bool { didSet { d.set(staleTintEnabled, forKey: "staleTintEnabled") } }
    var staleAfterMinutes: Double { didSet { d.set(staleAfterMinutes, forKey: "staleAfterMinutes") } }
    var showPanel: Bool { didSet { d.set(showPanel, forKey: "showPanel") } }
    var panelCollapsed: Bool { didSet { d.set(panelCollapsed, forKey: "panelCollapsed") } }
    /// Snapped to a side, the panel folds into a rail unless the user unfolded it.
    var sidebarExpanded: Bool { didSet { d.set(sidebarExpanded, forKey: "sidebarExpanded") } }
    /// Experimental: a Claude Code turn that stops with background agents still out stays running.
    var claudeBackgroundAgents: Bool { didSet { d.set(claudeBackgroundAgents, forKey: "claudeBackgroundAgents") } }
    /// Experimental: a finished turn counts as reviewed once its terminal pane is in front (`FocusWatcher`).
    var autoReviewOnFocus: Bool { didSet { d.set(autoReviewOnFocus, forKey: "autoReviewOnFocus") } }
    /// Height of the floating panel's list set with its resize grip, kept whatever the content; nil
    /// (the grip dragged all the way up) lets the list follow its content.
    var panelListHeight: CGFloat? { didSet { d.set(panelListHeight.map(Double.init), forKey: "panelListHeightManual") } }
    /// Width of the unfolded floating panel, set by dragging its side edge.
    var panelWidth: CGFloat { didSet { d.set(Double(panelWidth), forKey: "panelWidth") } }
    /// The floating panel's strip of figures (`RecentFigures`), under its header.
    var showRecentStats: Bool { didSet { d.set(showRecentStats, forKey: "showRecentStats") } }
    /// Trial, to go once one is chosen: how the main window's sidebar shows the way into Overview
    /// (`SidebarHead.Style`).
    var sidebarStyle: String { didSet { d.set(sidebarStyle, forKey: "sidebarStyleTrial") } }
    /// Session ids in the order the user arranged them (see `Board`).
    var manualOrder: [String] { didSet { d.set(Array(manualOrder.prefix(500)), forKey: "manualOrder") } }
    /// Pinned session ids, newest pin first; they sit above every status on the boards.
    var pinned: [String] { didSet { d.set(Array(pinned.prefix(100)), forKey: "pinnedSessions") } }
    var suppressWhenWaveFrontmost: Bool { didSet { d.set(suppressWhenWaveFrontmost, forKey: "suppressWhenWaveFrontmost") } }
    var waveTabSwitching: Bool { didSet { d.set(waveTabSwitching, forKey: "waveTabJump") } }
    /// The user answered "Not Now" to the note before the Accessibility prompt; a click on a card
    /// no longer asks.
    var accessibilityDeclined: Bool { didSet { d.set(accessibilityDeclined, forKey: "accessibilityDeclined") } }
    /// The setup guide was finished or closed; it no longer opens by itself.
    var setupDone: Bool { didSet { d.set(setupDone, forKey: "setupDone") } }
    /// The overview's first day of the week, as `Calendar.firstWeekday` (1 Sunday, 2 Monday, 7 Saturday).
    var firstWeekday: Int { didSet { d.set(firstWeekday, forKey: "firstWeekday") } }
    /// Lets the pi extension name unnamed sessions with the session's model. Kept as a file the
    /// extension can see (`Paths.piAutoTitleOff`), not in UserDefaults.
    var piAutoTitle: Bool {
        didSet {
            let off = Paths().piAutoTitleOff
            if piAutoTitle { try? FileManager.default.removeItem(at: off) }
            else {
                try? FileManager.default.createDirectory(at: off.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: off.path, contents: nil)
            }
        }
    }

    init() {
        d.register(defaults: [
            "stuckMinutes": 5.0, "approvalTimeout": 20.0, "idleVisibleMinutes": 1440.0,
            "flashEnabled": true, "flashAfterSeconds": Attention.flashAfter,
            "reviewFlashEnabled": true, "reviewFlashMinutes": Attention.reviewFlashAfter / 60,
            "staleTintEnabled": true, "staleAfterMinutes": Attention.staleAfter / 60,
            "showPanel": true, "suppressWhenWaveFrontmost": true, "waveTabJump": true,
            "showRecentStats": true, "claudeBackgroundAgents": true,
            "autoReviewOnFocus": true, "firstWeekday": 2,
        ])
        stuckMinutes = d.double(forKey: "stuckMinutes")
        approvalTimeout = d.double(forKey: "approvalTimeout")
        // Older builds allowed any 30-minute step; snap a stored value to the nearest choice.
        let stored = d.double(forKey: "idleVisibleMinutes")
        idleVisibleMinutes = Self.retentionChoices.min { abs($0 - stored) < abs($1 - stored) }!
        flashEnabled = d.bool(forKey: "flashEnabled")
        flashAfterSeconds = d.double(forKey: "flashAfterSeconds")
        reviewFlashEnabled = d.bool(forKey: "reviewFlashEnabled")
        reviewFlashMinutes = d.double(forKey: "reviewFlashMinutes")
        staleTintEnabled = d.bool(forKey: "staleTintEnabled")
        staleAfterMinutes = d.double(forKey: "staleAfterMinutes")
        showPanel = d.bool(forKey: "showPanel")
        panelCollapsed = d.bool(forKey: "panelCollapsed")
        sidebarExpanded = d.bool(forKey: "sidebarExpanded")
        claudeBackgroundAgents = d.bool(forKey: "claudeBackgroundAgents")
        autoReviewOnFocus = d.bool(forKey: "autoReviewOnFocus")
        panelListHeight = d.object(forKey: "panelListHeightManual") == nil ? nil : CGFloat(d.double(forKey: "panelListHeightManual"))
        panelWidth = d.object(forKey: "panelWidth") == nil ? 340 : CGFloat(d.double(forKey: "panelWidth"))
        showRecentStats = d.bool(forKey: "showRecentStats")
        sidebarStyle = d.string(forKey: "sidebarStyleTrial") ?? "pill"
        manualOrder = d.stringArray(forKey: "manualOrder") ?? []
        pinned = d.stringArray(forKey: "pinnedSessions") ?? []
        suppressWhenWaveFrontmost = d.bool(forKey: "suppressWhenWaveFrontmost")
        waveTabSwitching = d.bool(forKey: "waveTabJump")
        accessibilityDeclined = d.bool(forKey: "accessibilityDeclined")
        setupDone = d.bool(forKey: "setupDone")
        firstWeekday = Self.weekStarts.contains(d.integer(forKey: "firstWeekday")) ? d.integer(forKey: "firstWeekday") : 2
        piAutoTitle = !FileManager.default.fileExists(atPath: Paths().piAutoTitleOff.path)
    }

    var stuckConfig: StuckConfig { StuckConfig(silence: stuckMinutes * 60, toolDuration: stuckMinutes * 60) }
    /// How long reviewed sessions stay on the board, in minutes: 4, 8, 12 or 24 hours.
    static let retentionChoices: [Double] = [240, 480, 720, 1440]
    var idleVisibleSeconds: TimeInterval { idleVisibleMinutes * 60 }
    /// The days a week can start on: Monday, Sunday, Saturday.
    static let weekStarts = [2, 1, 7]
    /// The calendar the overview's weeks follow.
    var calendar: Calendar { var c = Calendar.current; c.firstWeekday = firstWeekday; return c }
    /// When a reviewed turn is bluest: halfway between turning blue and leaving the board.
    var stalePeakMinutes: Double { (staleAfterMinutes + idleVisibleMinutes) / 2 }
}

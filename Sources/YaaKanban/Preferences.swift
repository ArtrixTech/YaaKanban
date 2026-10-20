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
    /// A reviewed turn left alone turns blue from this long after it ended (see `Attention.staleness`).
    var staleTintEnabled: Bool { didSet { d.set(staleTintEnabled, forKey: "staleTintEnabled") } }
    var staleAfterMinutes: Double { didSet { d.set(staleAfterMinutes, forKey: "staleAfterMinutes") } }
    var panelOpacity: Double { didSet { d.set(panelOpacity, forKey: "panelOpacity") } }
    var showPanel: Bool { didSet { d.set(showPanel, forKey: "showPanel") } }
    var panelCollapsed: Bool { didSet { d.set(panelCollapsed, forKey: "panelCollapsed") } }
    /// Snapped to a side, the panel folds into a rail unless the user unfolded it.
    var sidebarExpanded: Bool { didSet { d.set(sidebarExpanded, forKey: "sidebarExpanded") } }
    /// Height of the floating panel's list, set with its resize grip; the list is shorter when its content is.
    var panelListHeight: CGFloat { didSet { d.set(Double(panelListHeight), forKey: "panelListHeight") } }
    /// Width of the unfolded floating panel, set by dragging its side edge.
    var panelWidth: CGFloat { didSet { d.set(Double(panelWidth), forKey: "panelWidth") } }
    /// Session ids in the order the user arranged them (see `Board`).
    var manualOrder: [String] { didSet { d.set(Array(manualOrder.prefix(500)), forKey: "manualOrder") } }
    var suppressWhenWaveFrontmost: Bool { didSet { d.set(suppressWhenWaveFrontmost, forKey: "suppressWhenWaveFrontmost") } }
    var waveTabSwitching: Bool { didSet { d.set(waveTabSwitching, forKey: "waveTabJump") } }

    init() {
        d.register(defaults: [
            "stuckMinutes": 5.0, "approvalTimeout": 20.0, "idleVisibleMinutes": 480.0, "panelOpacity": 0.95,
            "flashEnabled": true, "flashAfterSeconds": Attention.flashAfter,
            "staleTintEnabled": true, "staleAfterMinutes": Attention.staleAfter / 60,
            "showPanel": true, "suppressWhenWaveFrontmost": true, "waveTabJump": true,
        ])
        stuckMinutes = d.double(forKey: "stuckMinutes")
        approvalTimeout = d.double(forKey: "approvalTimeout")
        idleVisibleMinutes = d.double(forKey: "idleVisibleMinutes")
        flashEnabled = d.bool(forKey: "flashEnabled")
        flashAfterSeconds = d.double(forKey: "flashAfterSeconds")
        staleTintEnabled = d.bool(forKey: "staleTintEnabled")
        staleAfterMinutes = d.double(forKey: "staleAfterMinutes")
        panelOpacity = d.double(forKey: "panelOpacity")
        showPanel = d.bool(forKey: "showPanel")
        panelCollapsed = d.bool(forKey: "panelCollapsed")
        sidebarExpanded = d.bool(forKey: "sidebarExpanded")
        panelListHeight = d.object(forKey: "panelListHeight") == nil ? 560 : CGFloat(d.double(forKey: "panelListHeight"))
        panelWidth = d.object(forKey: "panelWidth") == nil ? 340 : CGFloat(d.double(forKey: "panelWidth"))
        manualOrder = d.stringArray(forKey: "manualOrder") ?? []
        suppressWhenWaveFrontmost = d.bool(forKey: "suppressWhenWaveFrontmost")
        waveTabSwitching = d.bool(forKey: "waveTabJump")
    }

    var stuckConfig: StuckConfig { StuckConfig(silence: stuckMinutes * 60, toolDuration: stuckMinutes * 60) }
    var idleVisibleSeconds: TimeInterval { idleVisibleMinutes * 60 }
    /// When a reviewed turn is bluest: halfway between turning blue and leaving the board.
    var stalePeakMinutes: Double { (staleAfterMinutes + idleVisibleMinutes) / 2 }
}

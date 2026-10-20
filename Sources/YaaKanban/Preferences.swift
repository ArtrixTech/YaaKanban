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
    var panelOpacity: Double { didSet { d.set(panelOpacity, forKey: "panelOpacity") } }
    var showPanel: Bool { didSet { d.set(showPanel, forKey: "showPanel") } }
    var panelCollapsed: Bool { didSet { d.set(panelCollapsed, forKey: "panelCollapsed") } }
    var suppressWhenWaveFrontmost: Bool { didSet { d.set(suppressWhenWaveFrontmost, forKey: "suppressWhenWaveFrontmost") } }
    var waveTabSwitching: Bool { didSet { d.set(waveTabSwitching, forKey: "waveTabSwitching") } }

    init() {
        d.register(defaults: [
            "stuckMinutes": 5.0, "approvalTimeout": 20.0, "idleVisibleMinutes": 30.0, "panelOpacity": 0.95,
            "showPanel": true, "suppressWhenWaveFrontmost": true, "waveTabSwitching": false,
        ])
        stuckMinutes = d.double(forKey: "stuckMinutes")
        approvalTimeout = d.double(forKey: "approvalTimeout")
        idleVisibleMinutes = d.double(forKey: "idleVisibleMinutes")
        panelOpacity = d.double(forKey: "panelOpacity")
        showPanel = d.bool(forKey: "showPanel")
        panelCollapsed = d.bool(forKey: "panelCollapsed")
        suppressWhenWaveFrontmost = d.bool(forKey: "suppressWhenWaveFrontmost")
        waveTabSwitching = d.bool(forKey: "waveTabSwitching")
    }

    var stuckConfig: StuckConfig { StuckConfig(silence: stuckMinutes * 60, toolDuration: stuckMinutes * 60) }
    var idleVisibleSeconds: TimeInterval { idleVisibleMinutes * 60 }
}

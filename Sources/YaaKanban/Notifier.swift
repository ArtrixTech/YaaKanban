import AppKit
import UserNotifications
import YaaCore

/// System notifications, with Allow/Deny actions for permission requests the app can decide.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Action { case open, allow, deny }
    var onAction: ((String, Action) -> Void)?

    private var center: UNUserNotificationCenter? {
        // UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`).
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        guard let center else { return }
        center.delegate = self
        let allow = UNNotificationAction(identifier: "allow", title: "允许一次")
        let deny = UNNotificationAction(identifier: "deny", title: "拒绝", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "permission", actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: "session", actions: [], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(_ alert: Alert, for s: SessionState, settings: Preferences) {
        guard let center else { return }
        if settings.suppressWhenWaveFrontmost, s.terminal?.isWave == true,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == TerminalJumper.waveBundleId { return }

        let c = UNMutableNotificationContent()
        let where_ = [s.agent.displayName, s.projectName].compactMap { $0 }.joined(separator: " · ")
        c.userInfo = ["key": s.id]
        c.categoryIdentifier = "session"
        switch alert {
        case .needsInput(let msg):
            c.title = "需要输入 — \(where_)"
            c.body = msg
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            if s.pendingPermission?.awaitingDecision == true { c.categoryIdentifier = "permission" }
        case .done(let last):
            c.title = "完成 — \(where_)"
            c.body = last.map { String($0.prefix(200)) } ?? s.title
        case .stuck(let reason):
            c.title = "可能卡住 — \(where_)"
            c.body = reason
        }
        center.add(UNNotificationRequest(identifier: "\(s.id)#\(UUID().uuidString)", content: c, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let key = response.notification.request.content.userInfo["key"] as? String ?? ""
        let action: Action = switch response.actionIdentifier {
        case "allow": .allow
        case "deny": .deny
        default: .open
        }
        Task { @MainActor in self.onAction?(key, action) }
        done()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }
}

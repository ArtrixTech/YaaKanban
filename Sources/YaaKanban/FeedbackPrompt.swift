import AppKit
import YaaIntegrations

/// 反馈…: shows the diagnostics that would go with the report, then opens a prefilled GitHub issue.
@MainActor
enum FeedbackPrompt {
    static func present(_ model: AppModel) {
        model.telemetry.count(.feedbackOpen)
        let report = model.diagnostics().markdown
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = String(localized: "Report a problem or suggest an idea")
        alert.informativeText = String(localized: "Opens a new GitHub issue in your browser (needs a GitHub account). The diagnostics below only hold versions and integration status, with no session content or paths.")
        let attach = NSButton(checkboxWithTitle: String(localized: "Attach diagnostics"), target: nil, action: nil)
        attach.state = .on
        let stack = NSStackView(views: [textBox(report, height: 150), attach])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        alert.accessoryView = stack
        alert.addButton(withTitle: String(localized: "Report a Problem"))
        alert.addButton(withTitle: String(localized: "Suggest an Idea"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        let kind: Feedback.Kind
        switch alert.runModal() {
        case .alertFirstButtonReturn: kind = .bug
        case .alertSecondButtonReturn: kind = .feature
        default: return
        }
        NSWorkspace.shared.open(Feedback.issueURL(kind, diagnostics: attach.state == .on ? report : nil))
    }

    /// Shows text to read and copy, e.g. the next telemetry report.
    static func show(title: String, text: String) {
        let alert = NSAlert()
        if let icon = BrandMark.image { alert.icon = icon }
        alert.messageText = title
        alert.accessoryView = textBox(text, height: 320)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Copy"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// A read-only, selectable, scrolling monospaced text box.
    private static func textBox(_ text: String, height: CGFloat) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 360, height: height)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: 360),
                                     scroll.heightAnchor.constraint(equalToConstant: height)])
        return scroll
    }
}

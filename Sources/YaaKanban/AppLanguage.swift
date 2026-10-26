import AppKit

/// The app's UI language. "System" follows macOS; any other choice is written as this app's own
/// `AppleLanguages`, which Bundle reads at launch, so a change takes effect after a relaunch.
enum AppLanguage {
    /// Shipped localizations (each has a `Resources/<code>.lproj`), in menu order, named in their own language.
    static let all: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("pt-BR", "Português (Brasil)"),
        ("ru", "Русский"),
    ]

    private static let key = "AppleLanguages"

    /// The chosen language code, or nil to follow the system. Reads only this app's domain, since
    /// `UserDefaults.standard` would also return the global setting.
    static var override: String? {
        get {
            guard let id = Bundle.main.bundleIdentifier,
                  let list = UserDefaults.standard.persistentDomain(forName: id)?[key] as? [String] else { return nil }
            return list.first
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// What the running process loaded, to tell whether a relaunch is still needed.
    static let atLaunch = override

    /// Opens a fresh copy of the app once this one has quit, then quits.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"",
                       "sh", "\(ProcessInfo.processInfo.processIdentifier)", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
